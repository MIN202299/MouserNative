import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// CGEventTap over scroll-wheel events that reproduces Mos's scrolling:
/// smooth scrolling, per-axis reversal and the accelerate / toggle / disable
/// hotkeys. Trackpad and Magic Mouse gestures pass through untouched.
/// Requires Accessibility permission.
///
/// Each wheel notch (at least `step` long, times `speed`) is added to a target
/// distance; every display frame scrolls a fixed fraction of what remains,
/// eased by a short filter, until the remainder falls inside the dead zone.
///
/// The tap and the frame clock run on a dedicated thread: a scroll tap on the
/// main thread makes every wheel event in the system wait whenever the UI is
/// busy (e.g. while this app's own settings window scrolls). All state below
/// is confined to that thread; settings arrive through `apply(_:)`.
final class ScrollEngine: NSObject, @unchecked Sendable {
    static let shared = ScrollEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var displayLink: CADisplayLink?
    private var linkRunning = false
    private let thread = ScrollThread()

    private let settingsLock = NSLock()
    private var sharedSettings = ScrollSettings()

    // Spring state: `buffer` is the target distance, `current` how far we got.
    private var buffer = (y: 0.0, x: 0.0)
    private var current = (y: 0.0, x: 0.0)
    private var lastDelta = (y: 0.0, x: 0.0)
    private var filter = EaseFilter()
    private var transition = ScrollSettings.transition(forDuration: ScrollSettings().duration)
    private var shiftToHorizontal = false
    private var template: CGEvent?
    /// App the wheel event was headed to; frames go straight to it.
    private var targetPID: pid_t = 0

    // Trackpad simulation state.
    private var simulateTrackpad = false
    private var phase = Phase.idle
    private var lastInputTime: CFTimeInterval = 0
    private var inputEnded = true

    private static let deadZone = 1.0
    private static let continuationThreshold: CFTimeInterval = 0.18
    private static let separationThreshold: CFTimeInterval = 0.45

    private enum Phase {
        case idle, tracking, momentum
    }

    private override init() {}

    var isRunning: Bool { eventTap != nil }

    /// Called on the main thread whenever the scrolling options change.
    func apply(_ settings: ScrollSettings) {
        settingsLock.lock()
        sharedSettings = settings
        settingsLock.unlock()
    }

    private var settings: ScrollSettings {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return sharedSettings
    }

    /// Call on the main thread.
    @MainActor
    func start() {
        guard eventTap == nil else { return }
        apply(ConfigStore.shared.scroll)
        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // The annotated session tap runs after the window server has picked the
        // event's target app, so `eventTargetUnixProcessID` is filled in and
        // smoothed frames can be delivered straight to that app (as Mos does).
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<ScrollEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            print("[Mouser] Scroll tap creation FAILED (accessibility not granted?)")
            return
        }
        eventTap = tap
        let runLoop = thread.runLoop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(runLoop.getCFRunLoop(), source, CFRunLoopMode.commonModes)

        // NSScreen is main-thread only, so the link is made here and then
        // driven by the scroll thread's run loop.
        if let link = NSScreen.main?.displayLink(target: self, selector: #selector(frame(_:))) {
            link.isPaused = true
            link.add(to: runLoop, forMode: .common)
            displayLink = link
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Mouser] Scroll tap active")
    }

    /// Call on the main thread.
    @MainActor
    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        let runLoop = thread.runLoop.getCFRunLoop()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, CFRunLoopMode.commonModes)
        }
        let link = displayLink
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            reset()
            link?.invalidate()
        }
        CFRunLoopWakeUp(runLoop)
        displayLink = nil
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel,
              !EventMarker.isInjected(event),
              !Self.isGestureScroll(event)
        else {
            return Unmanaged.passUnretained(event)
        }

        let settings = self.settings
        let flags = event.flags
        let dashHeld = settings.dash.map { flags.contains($0.flag) } ?? false
        let toggleHeld = settings.toggle.map { flags.contains($0.flag) } ?? false
        let blockHeld = settings.block.map { flags.contains($0.flag) } ?? false

        var wheel = WheelAxes(event)
        let hasY = wheel.y.usable != 0
        let hasX = wheel.x.usable != 0
        guard hasY || hasX else { return Unmanaged.passUnretained(event) }

        // With the toggle key held, vertical-only input behaves as horizontal.
        let shifting = toggleHeld && hasY && !hasX
        let reverseY = settings.reverse && (shifting ? settings.reverseHorizontal : settings.reverseVertical)
        let reverseX = settings.reverse && settings.reverseHorizontal
        if hasY && reverseY { wheel.y.negate() }
        if hasX && reverseX { wheel.x.negate() }

        let smooth = settings.smooth && !blockHeld
        let smoothY = smooth && hasY && (shifting ? settings.smoothHorizontal : settings.smoothVertical)
        let smoothX = smooth && hasX && settings.smoothHorizontal

        if smoothY || smoothX {
            let y = smoothY ? Self.atLeast(wheel.y.usable, settings.step) : 0
            let x = smoothX ? Self.atLeast(wheel.x.usable, settings.step) : 0
            update(
                event: event,
                y: y,
                x: x,
                speed: settings.speed,
                amplification: dashHeld ? ScrollSettings.dashAmplification : 1,
                settings: settings,
                shifting: toggleHeld
            )
        }

        let passY = hasY && !smoothY
        let passX = hasX && !smoothX
        guard passY || passX else { return nil }
        if smoothY { wheel.y.clear() }
        if smoothX { wheel.x.clear() }
        wheel.write(to: event)
        return Unmanaged.passUnretained(event)
    }

    /// Trackpads and Magic Mouse report gesture phases or scroll counts;
    /// already-continuous events (remote desktop, other smoothers) are left alone too.
    private static func isGestureScroll(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventScrollCount) != 0
            || event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    }

    private static func atLeast(_ value: Double, _ minimum: Double) -> Double {
        value > 0 ? max(value, minimum) : -max(-value, minimum)
    }

    private func update(
        event: CGEvent,
        y: Double,
        x: Double,
        speed: Double,
        amplification: Double,
        settings: ScrollSettings,
        shifting: Bool
    ) {
        transition = ScrollSettings.transition(forDuration: settings.effectiveDuration)
        shiftToHorizontal = shifting
        template = event.copy()
        targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))

        // Same direction keeps adding to the target; a reversal starts over.
        if y * lastDelta.y > 0 {
            buffer.y += y * speed * amplification
        } else {
            buffer.y = y * speed * amplification
            current.y = 0
        }
        if x * lastDelta.x > 0 {
            buffer.x += x * speed * amplification
        } else {
            buffer.x = x * speed * amplification
            current.x = 0
        }
        lastDelta = (y, x)

        let now = CACurrentMediaTime()
        simulateTrackpad = settings.simulateTrackpad
        if simulateTrackpad {
            let separated = inputEnded || phase == .idle || now - lastInputTime >= Self.separationThreshold
            if separated {
                if phase == .momentum { postPhase(scroll: 0, momentum: 3) }
                phase = .idle
            }
        }
        lastInputTime = now
        inputEnded = false
        startDisplayLink()
    }

    // MARK: - Frames

    private func startDisplayLink() {
        guard !linkRunning else { return }
        linkRunning = true
        displayLink?.isPaused = false
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let step = (
            y: (buffer.y - current.y) * transition,
            x: (buffer.x - current.x) * transition
        )
        current.y += step.y
        current.x += step.x

        var output = filter.fill(step)
        if shiftToHorizontal, output.y != 0, output.x == 0 {
            output = (0, output.y)
        }

        if simulateTrackpad, !inputEnded, now - lastInputTime > Self.continuationThreshold {
            inputEnded = true
            if phase == .tracking {
                postPhase(scroll: 4, momentum: 0)
                phase = .momentum
                momentumStarted = false
            }
        }

        if max(abs(output.y), abs(output.x)) > Self.deadZone {
            post(output)
        }

        let residual = max(abs(buffer.y - current.y), abs(buffer.x - current.x))
        let settled = max(abs(output.y), abs(output.x)) <= Self.deadZone
        if residual <= Self.deadZone && settled && (inputEnded || !simulateTrackpad) {
            finish()
        }
    }

    private var momentumStarted = false

    private func post(_ value: (y: Double, x: Double)) {
        var scrollPhase: Int64 = 0
        var momentumPhase: Int64 = 0
        if simulateTrackpad {
            switch phase {
            case .idle:
                scrollPhase = 1
                phase = .tracking
            case .tracking:
                scrollPhase = 2
            case .momentum:
                momentumPhase = momentumStarted ? 2 : 1
                momentumStarted = true
            }
        }
        send(value, scrollPhase: scrollPhase, momentumPhase: momentumPhase)
    }

    private func postPhase(scroll: Int64, momentum: Int64) {
        send((0, 0), scrollPhase: scroll, momentumPhase: momentum)
    }

    private func send(_ value: (y: Double, x: Double), scrollPhase: Int64, momentumPhase: Int64) {
        guard let event = template?.copy() else { return }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        // Like Mos: only the pixel deltas and the continuous flag change; apps
        // read pixel deltas for continuous events.
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: value.y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: value.x)
        EventMarker.tag(event)
        // Posting a copy into the session stream would also move the cursor
        // back to where the wheel turned, fighting the user's hand on every
        // frame. Deliver to the target app directly instead (as Mos does), so
        // the cursor is untouched and the glide stays on the original view.
        if targetPID > 1 {
            event.postToPid(targetPID)
        } else {
            if let cursor = CGEvent(source: nil)?.location {
                event.location = cursor
            }
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func finish() {
        if simulateTrackpad {
            switch phase {
            case .tracking: postPhase(scroll: 4, momentum: 0)
            case .momentum: postPhase(scroll: 0, momentum: 3)
            case .idle: break
            }
        }
        reset()
    }

    private func reset() {
        displayLink?.isPaused = true
        linkRunning = false
        buffer = (0, 0)
        current = (0, 0)
        lastDelta = (0, 0)
        filter = EaseFilter()
        template = nil
        targetPID = 0
        phase = .idle
        momentumStarted = false
        inputEnded = true
    }
}

/// A thread with its own run loop for the scroll tap and frame clock.
private final class ScrollThread: @unchecked Sendable {
    private let condition = NSCondition()
    private var loop: RunLoop?

    var runLoop: RunLoop {
        condition.lock()
        defer { condition.unlock() }
        if loop == nil {
            let thread = Thread { [weak self] in
                let rl = RunLoop.current
                rl.add(NSMachPort(), forMode: .default)
                guard let self else { return }
                self.condition.lock()
                self.loop = rl
                self.condition.signal()
                self.condition.unlock()
                rl.run()
            }
            thread.name = "com.duan.mouser.scroll"
            thread.qualityOfService = .userInteractive
            thread.start()
            while loop == nil {
                condition.wait()
            }
        }
        return loop!
    }
}

/// Smooths the first frames of a scroll so it starts without a jolt:
/// each output lags one frame behind and moves 23% toward the newest value.
private struct EaseFilter {
    private var y = 0.0
    private var x = 0.0

    mutating func fill(_ next: (y: Double, x: Double)) -> (y: Double, x: Double) {
        let output = (y: y, x: x)
        y += 0.23 * (next.y - y)
        x += 0.23 * (next.x - x)
        return output
    }
}

/// Per-axis wheel deltas in the three forms a scroll event carries.
private struct WheelAxes {
    struct Axis {
        var line: Int64
        var fixed: Double
        var point: Double

        /// Point delta if present, else fixed-point, else whole lines (as Mos does).
        var usable: Double {
            if point != 0 { return point }
            if fixed != 0 { return fixed }
            return Double(line)
        }

        mutating func negate() {
            line = -line; fixed = -fixed; point = -point
        }

        mutating func clear() {
            line = 0; fixed = 0; point = 0
        }
    }

    var y: Axis
    var x: Axis

    init(_ event: CGEvent) {
        y = Axis(
            line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            point: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        )
        x = Axis(
            line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            point: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        )
    }

    func write(to event: CGEvent) {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: y.line)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: x.line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: y.fixed)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: x.fixed)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: y.point)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: x.point)
    }
}

#if DEBUG
/// Debug-only end-to-end check, run with
/// `-scrollSelfTest <x> <y> <logPath>` (global top-left coordinates over a
/// window that logs the scroll events it receives). Uses Mouser's own
/// Accessibility permission to post real wheel notches and mouse moves, and
/// records where the cursor goes while smoothed frames are being delivered.
enum ScrollSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-scrollSelfTest"), args.count > i + 3,
              let x = Double(args[i + 1]), let y = Double(args[i + 2])
        else { return }
        let logPath = args[i + 3]
        Thread.detachNewThread {
            run(at: CGPoint(x: x, y: y), logPath: logPath)
        }
    }

    private static func run(at point: CGPoint, logPath: String) {
        var log = ""
        func note(_ line: String) {
            log += String(format: "%.3f ", CACurrentMediaTime()) + line + "\n"
            try? log.write(toFile: logPath, atomically: true, encoding: .utf8)
        }

        for _ in 0..<600 where !ScrollEngine.shared.isRunning {
            usleep(100_000)
        }
        guard ScrollEngine.shared.isRunning else {
            note("FAIL scroll tap not running (Accessibility?)")
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        var pointer = point
        func move(_ p: CGPoint) {
            pointer = p
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        func notch(_ lines: Int32, flags: CGEventFlags = []) {
            guard let e = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else { return }
            e.location = pointer // where the cursor was just moved, like a real wheel event
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

        note("BEGIN A smooth: 3 notches down")
        move(point); usleep(300_000)
        for _ in 0..<3 { notch(-1); usleep(80_000) }
        usleep(1_500_000)
        note("END A")

        note("BEGIN B cursor: 3 notches while moving 300px right")
        move(point); usleep(300_000)
        var samples: [Int] = []
        for step in 0...75 {
            if step % 25 == 0 { notch(-1) }
            move(CGPoint(x: point.x + Double(step) * 4, y: point.y))
            usleep(8_000)
            samples.append(Int(cursor().x - point.x))
        }
        usleep(300_000)
        let end = cursor()
        let backwards = zip(samples, samples.dropFirst()).filter { $1 < $0 - 2 }.count
        note("cursor offsets: " + samples.map(String.init).joined(separator: " "))
        note(String(format: "END B cursor ended at x=%.0f (expected %.0f), went backwards %d times", end.x, point.x + 300, backwards))

        note("BEGIN C dash: 1 notch up with Option held")
        move(point); usleep(300_000)
        notch(1, flags: .maskAlternate)
        usleep(1_500_000)
        note("END C")

        note("BEGIN D plain: 1 notch up")
        move(point); usleep(300_000)
        notch(1)
        usleep(1_500_000)
        note("END D")

        note("BEGIN E reverse: 2 notches down, then 1 up mid-glide")
        notch(-1); usleep(60_000); notch(-1); usleep(150_000); notch(1)
        usleep(1_500_000)
        note("END E")
        note("DONE")
    }
}
#endif

import CoreGraphics
import Foundation

/// CGEventTap that swallows remapped standard mouse buttons (middle/back/forward)
/// and dispatches their actions. Requires Accessibility permission.
@MainActor
final class ButtonInterceptor {
    static let shared = ButtonInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    var isRunning: Bool { eventTap != nil }

    func start() {
        guard eventTap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<ButtonInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            print("[Mouser] Event tap creation FAILED (accessibility not granted?)")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Mouser] Event tap active")
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .otherMouseDown || type == .otherMouseUp else {
            return Unmanaged.passUnretained(event)
        }
        if EventMarker.isInjected(event) {
            return Unmanaged.passUnretained(event)
        }
        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard let button = MouseButton(cgButtonNumber: buttonNumber) else {
            return Unmanaged.passUnretained(event)
        }
        let action = ConfigStore.shared.action(for: button)
        print("[Mouser] Button \(buttonNumber) \(type == .otherMouseDown ? "down" : "up") -> \(action.rawValue)")
        guard action != .default else {
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseDown {
            ActionPerformer.shared.perform(action)
        }
        return nil
    }
}

private extension MouseButton {
    init?(cgButtonNumber: Int) {
        switch cgButtonNumber {
        case 2: self = .middle
        case 3: self = .back
        case 4: self = .forward
        default: return nil
        }
    }
}

import CoreGraphics
import Foundation

/// A modifier key held while scrolling to trigger a scroll hotkey.
enum ScrollModifier: String, CaseIterable, Identifiable, Codable {
    case option
    case shift
    case command
    case control
    case function

    var id: Self { self }

    var title: String {
        switch self {
        case .option: "⌥ Option"
        case .shift: "⇧ Shift"
        case .command: "⌘ Command"
        case .control: "⌃ Control"
        case .function: "fn Function"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .option: .maskAlternate
        case .shift: .maskShift
        case .command: .maskCommand
        case .control: .maskControl
        case .function: .maskSecondaryFn
        }
    }

    /// The modifier a `flagsChanged` event just pressed, if exactly one is down.
    static func pressed(in flags: CGEventFlags) -> ScrollModifier? {
        let held = allCases.filter { flags.contains($0.flag) }
        return held.count == 1 ? held[0] : nil
    }
}

/// Mouse-wheel behaviour applied by `ScrollEngine`, mirroring Mos's scrolling
/// options and defaults. Trackpads are never touched.
struct ScrollSettings: Codable, Equatable {
    var smooth = true
    var smoothVertical = true
    var smoothHorizontal = true
    /// Emit trackpad-style scroll and momentum phases (Beta in Mos).
    var simulateTrackpad = false

    var reverse = true
    var reverseVertical = true
    var reverseHorizontal = true

    /// Hold to scroll faster (×5).
    var dash: ScrollModifier? = .option
    /// Hold to turn vertical scrolling into horizontal scrolling.
    var toggle: ScrollModifier? = .shift
    /// Hold to disable smooth scrolling.
    var block: ScrollModifier? = .command

    /// Minimum distance of a single scroll.
    var step = 33.6
    /// Tracking speed gain of continuous scrolling.
    var speed = 2.70
    /// Easing duration of scrolling.
    var duration = 4.35
    /// Duration to restore when trackpad simulation is turned off again.
    var durationBeforeSimulateTrackpad: Double?

    static let stepRange = 0.01...100.0
    static let speedRange = 1.0...10.0
    static let durationRange = 1.0...5.0
    static let simulateTrackpadDuration = 4.75
    static let dashAmplification = 5.0

    /// Fraction of the remaining distance scrolled per display frame.
    static func transition(forDuration duration: Double) -> Double {
        let upperLimit = durationRange.upperBound + 0.2
        let value = 1 - (duration / upperLimit).squareRoot()
        return (1000 * value).rounded() / 1000
    }

    /// The duration actually in effect (locked while simulating a trackpad).
    var effectiveDuration: Double {
        simulateTrackpad ? Self.simulateTrackpadDuration : duration
    }

    mutating func setSimulateTrackpad(_ isOn: Bool) {
        guard isOn != simulateTrackpad else { return }
        simulateTrackpad = isOn
        if isOn {
            durationBeforeSimulateTrackpad = duration
            duration = Self.simulateTrackpadDuration
        } else {
            if let previous = durationBeforeSimulateTrackpad {
                duration = previous
            }
            durationBeforeSimulateTrackpad = nil
        }
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case smooth, smoothVertical, smoothHorizontal, simulateTrackpad
        case reverse, reverseVertical, reverseHorizontal
        case dash, toggle, block
        case step, speed, duration, durationBeforeSimulateTrackpad
    }

    // Decode field-by-field so settings saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScrollSettings()
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? d.smooth
        smoothVertical = try c.decodeIfPresent(Bool.self, forKey: .smoothVertical) ?? d.smoothVertical
        smoothHorizontal = try c.decodeIfPresent(Bool.self, forKey: .smoothHorizontal) ?? d.smoothHorizontal
        simulateTrackpad = try c.decodeIfPresent(Bool.self, forKey: .simulateTrackpad) ?? d.simulateTrackpad
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? d.reverse
        reverseVertical = try c.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? d.reverseVertical
        reverseHorizontal = try c.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? d.reverseHorizontal
        dash = c.contains(.dash) ? try c.decodeIfPresent(ScrollModifier.self, forKey: .dash) : d.dash
        toggle = c.contains(.toggle) ? try c.decodeIfPresent(ScrollModifier.self, forKey: .toggle) : d.toggle
        block = c.contains(.block) ? try c.decodeIfPresent(ScrollModifier.self, forKey: .block) : d.block
        step = try c.decodeIfPresent(Double.self, forKey: .step) ?? d.step
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? d.duration
        durationBeforeSimulateTrackpad = try c.decodeIfPresent(Double.self, forKey: .durationBeforeSimulateTrackpad)
    }

    // Cleared hotkeys are written as explicit nulls so they stay cleared.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(smooth, forKey: .smooth)
        try c.encode(smoothVertical, forKey: .smoothVertical)
        try c.encode(smoothHorizontal, forKey: .smoothHorizontal)
        try c.encode(simulateTrackpad, forKey: .simulateTrackpad)
        try c.encode(reverse, forKey: .reverse)
        try c.encode(reverseVertical, forKey: .reverseVertical)
        try c.encode(reverseHorizontal, forKey: .reverseHorizontal)
        try c.encode(dash, forKey: .dash)
        try c.encode(toggle, forKey: .toggle)
        try c.encode(block, forKey: .block)
        try c.encode(step, forKey: .step)
        try c.encode(speed, forKey: .speed)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(durationBeforeSimulateTrackpad, forKey: .durationBeforeSimulateTrackpad)
    }
}

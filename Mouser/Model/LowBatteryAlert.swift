import Foundation

/// Decides when to warn about a low mouse battery. It warns once when the
/// level drops to the threshold, once more at the critical level, and re-arms
/// only after the mouse charges or climbs back above the threshold, so a
/// reading that hovers around the line doesn't spam notifications.
struct LowBatteryAlertTracker: Equatable {
    enum Alert: Equatable {
        case low(level: Int)
        case critical(level: Int)
    }

    static let criticalLevel = 5
    static let thresholdRange: ClosedRange<Int> = 5...50
    static let defaultThreshold = 20

    private var warnedLow = false
    private var warnedCritical = false

    mutating func evaluate(level: Int, charging: Bool, threshold: Int) -> Alert? {
        if charging || level > threshold {
            warnedLow = false
            warnedCritical = false
            return nil
        }
        if level <= Self.criticalLevel, threshold > Self.criticalLevel {
            guard !warnedCritical else { return nil }
            warnedCritical = true
            warnedLow = true
            return .critical(level: level)
        }
        guard !warnedLow else { return nil }
        warnedLow = true
        return .low(level: level)
    }
}

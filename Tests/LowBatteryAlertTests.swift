import Foundation

@main
struct LowBatteryAlertTests {
    static func main() {
        var tracker = LowBatteryAlertTracker()

        precondition(tracker.evaluate(level: 50, charging: false, threshold: 20) == nil)
        precondition(tracker.evaluate(level: 20, charging: false, threshold: 20) == .low(level: 20),
                     "Reaching the threshold must alert")
        precondition(tracker.evaluate(level: 19, charging: false, threshold: 20) == nil,
                     "Further drops above critical must not re-alert")
        precondition(tracker.evaluate(level: 5, charging: false, threshold: 20) == .critical(level: 5),
                     "Critical level must alert once more")
        precondition(tracker.evaluate(level: 4, charging: false, threshold: 20) == nil)

        // Charging re-arms.
        precondition(tracker.evaluate(level: 6, charging: true, threshold: 20) == nil)
        precondition(tracker.evaluate(level: 6, charging: false, threshold: 20) == .low(level: 6))

        // Hovering at the threshold doesn't spam; climbing above re-arms.
        tracker = LowBatteryAlertTracker()
        precondition(tracker.evaluate(level: 15, charging: false, threshold: 15) == .low(level: 15))
        precondition(tracker.evaluate(level: 15, charging: false, threshold: 15) == nil)
        precondition(tracker.evaluate(level: 16, charging: false, threshold: 15) == nil)
        precondition(tracker.evaluate(level: 15, charging: false, threshold: 15) == .low(level: 15))

        // First reading already critical goes straight to the critical alert.
        tracker = LowBatteryAlertTracker()
        precondition(tracker.evaluate(level: 3, charging: false, threshold: 20) == .critical(level: 3))
        precondition(tracker.evaluate(level: 3, charging: false, threshold: 20) == nil)

        // Threshold at the critical level alerts just once.
        tracker = LowBatteryAlertTracker()
        precondition(tracker.evaluate(level: 5, charging: false, threshold: 5) == .low(level: 5))
        precondition(tracker.evaluate(level: 2, charging: false, threshold: 5) == nil)

        print("LowBatteryAlertTests passed")
    }
}

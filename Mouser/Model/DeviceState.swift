import Foundation

/// Observable snapshot of the connected mouse, consumed by UI.
@MainActor
@Observable
final class DeviceState {
    static let shared = DeviceState()

    var connected = false
    var deviceName = ""
    var transport = ""
    var batteryLevel: Int?
    var batteryCharging = false
    var dpi: Int?
    var smartShiftSupported = false
    var smartShiftEnabled = false
    var smartShiftThreshold = 25
    var wheelModeByte: UInt8?

    static let dpiRange: ClosedRange<Int> = 200...8000

    var batteryIconName: String {
        guard let batteryLevel else { return "battery.0" }
        if batteryCharging { return "battery.100percent.bolt" }
        switch batteryLevel {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default: return "battery.25"
        }
    }
}

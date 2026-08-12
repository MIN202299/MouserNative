import Foundation

enum HIDPP {
    static let vendorID = 0x046D
    static let productIDAnywhere3S = 0xB037

    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let longPayloadLength = 19
    static let directDeviceIndex: UInt8 = 0xFF
    static let softwareID: UInt8 = 0x0A

    enum Feature {
        static let iRoot: UInt16 = 0x0000
        static let deviceName: UInt16 = 0x0005
        static let batteryStatus: UInt16 = 0x1000
        static let unifiedBattery: UInt16 = 0x1004
        static let reprogControlsV4: UInt16 = 0x1B04
        static let smartShift: UInt16 = 0x2110
        static let smartShiftEnhanced: UInt16 = 0x2111
        static let hiResWheel: UInt16 = 0x2120
        static let hiResWheelEnhanced: UInt16 = 0x2121
        static let adjustableDPI: UInt16 = 0x2201
    }

    enum CID {
        static let gesture: UInt16 = 0x00C3
        static let modeShift: UInt16 = 0x00C4
        static let virtualGesture: UInt16 = 0x00D7
        static let dpiSwitch: UInt16 = 0x00FD
    }

    static let divertButtonFlags: UInt8 = 0x03
    static let undivertFlags: UInt8 = 0x02

    enum SmartShiftMode {
        static let freespin: UInt8 = 0x01
        static let ratchet: UInt8 = 0x02
        static let disableThreshold: UInt8 = 0xFF
        static let thresholdRange: ClosedRange<Int> = 1...50
    }

    enum WheelModeBit {
        static let target: UInt8 = 0x01
        static let resolution: UInt8 = 0x02
        static let invert: UInt8 = 0x04
    }
}

enum HIDPPError: Error, LocalizedError {
    case timeout
    case deviceError(UInt8)
    case notConnected
    case openFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .timeout: "HID++ request timed out"
        case .deviceError(let code): String(format: "HID++ device error 0x%02X", code)
        case .notConnected: "Device not connected"
        case .openFailed(let code): String(format: "IOHIDDeviceOpen failed: 0x%08X", code)
        }
    }
}

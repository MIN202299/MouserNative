import Foundation
import IOKit
import IOKit.hid

// HID++ ping test: try output report payload with and without the report ID byte.
// Usage: swiftc pingtest.swift -o pingtest && ./pingtest

let vendorID = 0x046D
let reportID: UInt8 = 0x11

var receivedReports: [(UInt32, [UInt8])] = []

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("manager open failed: \(String(format: "0x%08X", openResult))")
    exit(1)
}

guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
    print("no Logitech devices")
    exit(1)
}

print("found \(set.count) device(s)")

for device in set {
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    print("device: \(product) PID=0x\(String(pid, radix: 16))")

    guard pid == 0xB037 else { continue }

    let res = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard res == kIOReturnSuccess else {
        print("  open failed: \(String(format: "0x%08X", res))")
        continue
    }

    // List report elements to understand the descriptor
    if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
        var reportIDs = Set<UInt32>()
        for el in elements {
            let rid = IOHIDElementGetReportID(el)
            if rid != 0 { reportIDs.insert(rid) }
        }
        print("  report IDs in descriptor: \(reportIDs.sorted().map { String(format: "0x%02X", $0) })")
    }

    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue as CFString)

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    let callback: IOHIDReportCallback = { _, result, _, _, rid, report, length in
        guard result == kIOReturnSuccess, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        receivedReports.append((rid, bytes))
    }
    IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, callback, nil)

    func tryWrite(_ label: String, _ bytes: [UInt8], reportID: UInt8) {
        receivedReports.removeAll()
        let res = bytes.withUnsafeBufferPointer { ptr in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), ptr.baseAddress!, bytes.count)
        }
        print("  [\(label)] SetReport result: \(String(format: "0x%08X", res)) (kIOReturnSuccess=0x0)")
        // pump run loop for 600ms
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, true)
        }
        if receivedReports.isEmpty {
            print("  [\(label)] no input reports")
        } else {
            for (rid, bytes) in receivedReports {
                print("  [\(label)] input report id=0x\(String(format: "%02X", rid)) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
        }
    }

    // IRoot getProtocolVersion: feat 0x00, func 1, sw 0x0A -> [devIdx=0xFF, 0x00, 0x1A, 0,0,0...]
    var payload = [UInt8](repeating: 0, count: 19)
    payload[0] = 0xFF
    payload[1] = 0x00
    payload[2] = 0x1A

    tryWrite("no-report-id-19B", payload, reportID: reportID)

    var withID = [reportID] + payload
    tryWrite("with-report-id-20B", withID, reportID: reportID)

    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    buffer.deallocate()
}
print("done")

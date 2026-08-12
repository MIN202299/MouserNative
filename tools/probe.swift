import Foundation
import IOKit
import IOKit.hid

// HID++ feature probe for MX Anywhere 3S: dumps full response params per function.
// Serial request/response with software-id matching, report-ID-inclusive buffers.

let vendorID = 0x046D
let reportID: UInt8 = 0x11
let swID: UInt8 = 0x0A

setbuf(stdout, nil)

var device: IOHIDDevice?
var pendingCont: CheckedContinuation<[UInt8], Never>?
var pendingFeat: UInt8 = 0
var pendingFunc: UInt8 = 0

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

func sendRequest(feat: UInt8, fn: UInt8, params: [UInt8] = [], timeout: TimeInterval = 1.0) async -> [UInt8]? {
    var payload = [UInt8](repeating: 0, count: 20)
    payload[0] = reportID
    payload[1] = 0xFF
    payload[2] = feat
    payload[3] = ((fn & 0x0F) << 4) | swID
    for (i, b) in params.enumerated() where 4 + i < 20 { payload[4 + i] = b }
    let res = payload.withUnsafeBufferPointer { ptr in
        IOHIDDeviceSetReport(device!, kIOHIDReportTypeOutput, CFIndex(reportID), ptr.baseAddress!, payload.count)
    }
    guard res == kIOReturnSuccess else { print("  write failed \(String(format: "0x%08X", res))"); return nil }

    return await withCheckedContinuation { cont in
        pendingCont = cont
        pendingFeat = feat
        pendingFunc = fn
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if let pending = pendingCont, pendingFeat == feat {
                pendingCont = nil
                pending.resume(returning: [])
            }
        }
    }
}

func findFeature(_ id: UInt16) async -> UInt8? {
    guard let p = await sendRequest(feat: 0x00, fn: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF), 0]),
          let idx = p.first, idx != 0 else { return nil }
    return idx
}

// MARK: - setup

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { print("no devices"); exit(1) }

for d in set {
    let pid = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0
    if pid == 0xB037 { device = d }
}
guard let device else { print("mouse not found"); exit(1) }
guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { print("open failed"); exit(1) }

IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue as CFString)
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
let callback: IOHIDReportCallback = { _, result, _, _, rid, report, length in
    guard result == kIOReturnSuccess, length > 0, rid == 0x11 else { return }
    var bytes = Array(UnsafeBufferPointer(start: report, count: length))
    if bytes.first == 0x11 { bytes.removeFirst() }
    guard bytes.count >= 3 else { return }
    let feat = bytes[1]
    let fsw = bytes[2]
    let fn = (fsw >> 4) & 0x0F
    let sw = fsw & 0x0F
    let params = Array(bytes.dropFirst(3))
    if let cont = pendingCont, sw == swID, feat == pendingFeat, fn == pendingFunc || fn == (pendingFunc + 1) & 0x0F {
        pendingCont = nil
        cont.resume(returning: params)
    } else if feat == 0xFF {
        print("  [error report] origFeat=0x\(String(format: "%02X", params.first ?? 0)) code=0x\(String(format: "%02X", params.count > 1 ? params[1] : 0))")
    }
}
IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, callback, nil)

func run(_ block: @escaping () async -> Void) {
    Task {
        await block()
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
    CFRunLoopRun()
}

run {
    // ping
    if let p = await sendRequest(feat: 0, fn: 1, params: [0, 0, 0]) {
        print("ping ok, protocol \(p.count > 1 ? "\(p[0]).\(p[1])" : "?")")
    }

    let features: [(String, UInt16)] = [
        ("REPROG_V4", 0x1B04), ("ADJ_DPI", 0x2201), ("UNIFIED_BATT", 0x1004),
        ("BATT_STATUS", 0x1000), ("SMART_SHIFT", 0x2110), ("SMART_SHIFT_ENH", 0x2111),
        ("HIRES_WHEEL", 0x2120), ("HIRES_WHEEL_ENH", 0x2121), ("DEVICE_NAME", 0x0005),
    ]
    var idx: [String: UInt8] = [:]
    for (name, id) in features {
        if let i = await findFeature(id) { idx[name] = i }
        print("feature \(name) (0x\(String(format: "%04X", id))) -> index \(idx[name].map { String(format: "0x%02X", $0) } ?? "none")")
    }

    if let batt = idx["UNIFIED_BATT"] {
        for fn: UInt8 in [0, 1] {
            let p = await sendRequest(feat: batt, fn: fn) ?? []
            print("UNIFIED_BATT fn\(fn): [\(hex(p))]")
        }
    }
    if let batt = idx["BATT_STATUS"] {
        let p = await sendRequest(feat: batt, fn: 0) ?? []
        print("BATT_STATUS fn0: [\(hex(p))]")
    }
    if let dpi = idx["ADJ_DPI"] {
        for fn: UInt8 in [0, 1, 2] {
            let p = await sendRequest(feat: dpi, fn: fn, params: [0x00]) ?? []
            print("ADJ_DPI fn\(fn): [\(hex(p))]")
        }
    }
    if let ss = idx["SMART_SHIFT"] ?? idx["SMART_SHIFT_ENH"] {
        for fn: UInt8 in [0, 1] {
            let p = await sendRequest(feat: ss, fn: fn) ?? []
            print("SMART_SHIFT fn\(fn): [\(hex(p))]")
        }
    }
    if let wheel = idx["HIRES_WHEEL"] ?? idx["HIRES_WHEEL_ENH"] {
        for fn: UInt8 in [0, 1] {
            let p = await sendRequest(feat: wheel, fn: fn) ?? []
            print("HIRES_WHEEL fn\(fn): [\(hex(p))]")
        }
    }
    if let reprog = idx["REPROG_V4"] {
        if let count = (await sendRequest(feat: reprog, fn: 0))?.first {
            print("REPROG_V4 control count: \(count)")
            for i in 0..<min(count, 12) {
                let p = await sendRequest(feat: reprog, fn: 1, params: [i]) ?? []
                if p.count >= 9 {
                    let cid = UInt16(p[0]) << 8 | UInt16(p[1])
                    let flags = UInt16(p[4]) | UInt16(p[8]) << 8
                    print("  control[\(i)] cid=0x\(String(format: "%04X", cid)) flags=0x\(String(format: "%04X", flags))")
                }
            }
        }
    }
    print("probe done")
}

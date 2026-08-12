import Foundation
import IOKit
import IOKit.hid

/// Dedicated run loop thread: every IOHIDDevice is scheduled here so input
/// reports never touch the main thread.
final class HIDRunLoop {
    static let shared = HIDRunLoop()

    private let condition = NSCondition()
    private var runLoop: RunLoop?
    private var started = false

    func runLoopForScheduling() -> RunLoop {
        condition.lock()
        if !started {
            started = true
            let thread = Thread { [weak self] in
                let rl = RunLoop.current
                rl.add(NSMachPort(), forMode: .default)
                guard let self else { return }
                self.condition.lock()
                self.runLoop = rl
                self.condition.signal()
                self.condition.unlock()
                rl.run()
            }
            thread.name = "com.duan.mouser.hid"
            thread.qualityOfService = .userInteractive
            thread.start()
        }
        while runLoop == nil {
            condition.wait()
        }
        let rl = runLoop!
        condition.unlock()
        return rl
    }
}

private let hidInputReportCallback: IOHIDReportCallback = { context, result, _, _, reportID, report, length in
    guard result == kIOReturnSuccess, length > 0, let context else { return }
    let handle = Unmanaged<HIDDeviceHandle>.fromOpaque(context).takeUnretainedValue()
    var payload = Array(UnsafeBufferPointer(start: report, count: length))
    // This BLE transport returns input reports with the report ID byte included.
    if payload.first == UInt8(reportID & 0xFF) {
        payload.removeFirst()
    }
    handle.onReport?(UInt8(reportID & 0xFF), payload)
}

private let hidRemovalCallback: IOHIDCallback = { context, _, _ in
    guard let context else { return }
    let handle = Unmanaged<HIDDeviceHandle>.fromOpaque(context).takeUnretainedValue()
    handle.onRemoved?()
}

/// Thin wrapper over one IOHIDDevice: output reports via IOHIDDeviceSetReport,
/// input reports via the registered callback (payload excludes report ID).
final class HIDDeviceHandle {
    let raw: IOHIDDevice
    let productID: Int
    let productName: String
    let transport: String

    var onReport: ((_ reportID: UInt8, _ payload: [UInt8]) -> Void)?
    var onRemoved: (() -> Void)?

    private var inputBuffer: UnsafeMutablePointer<UInt8>
    private let inputBufferLength = 64
    private var scheduledRunLoop: CFRunLoop?
    private var isOpen = false

    init(device: IOHIDDevice) {
        raw = device
        productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        productName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech Device"
        transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
        inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputBufferLength)
    }

    deinit {
        inputBuffer.deallocate()
    }

    func open(scheduleOn runLoop: RunLoop) throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(raw, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDPPError.openFailed(result) }
        isOpen = true
        let cfRunLoop = runLoop.getCFRunLoop()
        scheduledRunLoop = cfRunLoop
        IOHIDDeviceScheduleWithRunLoop(raw, cfRunLoop, CFRunLoopMode.defaultMode.rawValue as CFString)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(raw, inputBuffer, inputBufferLength, hidInputReportCallback, context)
        IOHIDDeviceRegisterRemovalCallback(raw, hidRemovalCallback, context)
    }

    /// Sends an output report. This BLE transport expects the report ID byte
    /// included as the first buffer byte (unlike the hidapi convention).
    func write(reportID: UInt8, payload: [UInt8]) -> Bool {
        guard isOpen else { return false }
        let buffer = [reportID] + payload
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return false }
            return IOHIDDeviceSetReport(raw, kIOHIDReportTypeOutput, CFIndex(reportID), base, buffer.count) == kIOReturnSuccess
        }
    }

    func close() {
        guard isOpen else { return }
        if let runLoop = scheduledRunLoop {
            IOHIDDeviceUnscheduleFromRunLoop(raw, runLoop, CFRunLoopMode.defaultMode.rawValue as CFString)
        }
        IOHIDDeviceClose(raw, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
        scheduledRunLoop = nil
    }
}

/// Enumerates Logitech devices visible through IOHIDManager.
enum HIDDiscovery {
    static func matchingDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: HIDPP.vendorID] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return [] }
        return Array(set)
    }
}

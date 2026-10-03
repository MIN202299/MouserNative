import Foundation
import IOKit
import IOKit.hid

/// Owns device discovery, the HID++ session, feature reads/writes and polling.
@MainActor
@Observable
final class DeviceManager {
    static let shared = DeviceManager()

    private(set) var session: HIDPPSession?
    private var handle: HIDDeviceHandle?
    private var hidManager: IOHIDManager?

    private var reprogIndex: UInt8?
    private var dpiIndex: UInt8?
    private var batteryIndex: UInt8?
    private var batteryIsUnified = false
    private var smartShiftIndex: UInt8?
    private var smartShiftEnhanced = false
    private var wheelIndex: UInt8?

    private var batteryTimer: Timer?
    private var divertedCIDs = Set<UInt16>()
    private var attemptedDevices = Set<ObjectIdentifier>()
    private var connecting = false
    private var scanning = false
    private var isSuspended = false
    private var retryTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isSuspended, !scanning else { return }
        scanning = true
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: HIDPP.vendorID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let manager = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in manager.deviceAppeared(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager
        scan()
    }

    func scan() {
        guard !isSuspended, handle == nil else { return }
        let devices = HIDDiscovery.matchingDevices()
        print("[Mouser] Scan: \(devices.count) Logitech device(s) found")
        if devices.isEmpty {
            scheduleRetryScan()
            return
        }
        for device in devices {
            let candidate = HIDDeviceHandle(device: device)
            let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            print("[Mouser]   candidate: \(candidate.productName) PID=0x\(String(candidate.productID, radix: 16)) transport=\(candidate.transport) usagePage=0x\(String(usagePage, radix: 16))")
            attemptConnection(to: device)
        }
    }

    private func deviceAppeared(_ device: IOHIDDevice) {
        guard !isSuspended, handle == nil else { return }
        attemptConnection(to: device)
    }

    private func attemptConnection(to device: IOHIDDevice) {
        guard !isSuspended, !connecting, handle == nil else { return }
        let deviceID = ObjectIdentifier(device)
        guard !attemptedDevices.contains(deviceID) else { return }
        attemptedDevices.insert(deviceID)
        connecting = true

        let candidate = HIDDeviceHandle(device: device)
        do {
            try candidate.open(scheduleOn: HIDRunLoop.shared.runLoopForScheduling())
        } catch {
            print("[Mouser]   open failed: \(error.localizedDescription)")
            attemptedDevices.remove(deviceID)
            connecting = false
            return
        }
        let newSession = HIDPPSession(device: candidate) { [weak self] message in
            Task { @MainActor in self?.handleNotification(message) }
        }
        candidate.onRemoved = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.attemptedDevices.remove(deviceID)
                self.connecting = false
                if self.handle === candidate {
                    self.deviceDisconnected()
                }
            }
        }
        Task {
            if await self.completeConnection(handle: candidate, session: newSession) == false {
                print("[Mouser]   ping failed for \(candidate.productName) PID=0x\(String(candidate.productID, radix: 16))")
                candidate.close()
                self.attemptedDevices.remove(deviceID)
                self.connecting = false
                self.scheduleRetryScan()
                return
            }
            self.connecting = false
        }
    }

    private func scheduleRetryScan() {
        guard !isSuspended else { return }
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !self.isSuspended,
                  self.handle == nil, !self.connecting else { return }
            self.scan()
        }
    }

    /// Probes HID++ and discovers features. Runs off-main via the session actor.
    private func completeConnection(handle candidate: HIDDeviceHandle, session newSession: HIDPPSession) async -> Bool {
        let handle = candidate
        let session = newSession
        guard await session.ping() else { return false }
        guard !isSuspended, self.handle == nil else {
            await session.close()
            return false
        }
        self.handle = handle
        self.session = session

        async let reprog = session.findFeature(HIDPP.Feature.reprogControlsV4)
        async let dpi = session.findFeature(HIDPP.Feature.adjustableDPI)
        async let unifiedBattery = session.findFeature(HIDPP.Feature.unifiedBattery)
        async let basicBattery = session.findFeature(HIDPP.Feature.batteryStatus)
        async let smartShiftE = session.findFeature(HIDPP.Feature.smartShiftEnhanced)
        async let smartShiftB = session.findFeature(HIDPP.Feature.smartShift)
        async let wheelE = session.findFeature(HIDPP.Feature.hiResWheelEnhanced)
        async let wheelB = session.findFeature(HIDPP.Feature.hiResWheel)

        let features = await (reprog, dpi, unifiedBattery, basicBattery, smartShiftE, smartShiftB, wheelE, wheelB)

        reprogIndex = features.0
        dpiIndex = features.1
        batteryIndex = features.2 ?? features.3
        batteryIsUnified = features.2 != nil
        smartShiftIndex = features.4 ?? features.5
        smartShiftEnhanced = features.4 != nil
        wheelIndex = features.6 ?? features.7

        DeviceState.shared.connected = true
        DeviceState.shared.deviceName = handle.productName
        DeviceState.shared.transport = handle.transport
        DeviceState.shared.smartShiftSupported = smartShiftIndex != nil

        print("[Mouser] Connected: \(handle.productName) (PID 0x\(String(handle.productID, radix: 16)), \(handle.transport))")
        print("[Mouser] Features: reprog=\(reprogIndex.map(String.init) ?? "-") dpi=\(dpiIndex.map(String.init) ?? "-") battery=\(batteryIndex.map(String.init) ?? "-") smartShift=\(smartShiftIndex.map(String.init) ?? "-") wheel=\(wheelIndex.map(String.init) ?? "-")")

        await refreshAll()
        await restorePreferredDPI()
        await applyButtonConfiguration()
        await setWheelInvertVertical(ConfigStore.shared.invertScrollVertical)

        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBattery() }
        }
        return true
    }

    /// Quiesces all Logitech HID traffic before macOS enters sleep. Button
    /// diversion remains stored in the mouse firmware and is restored on wake.
    func suspendForSleep() {
        guard !isSuspended else { return }
        isSuspended = true
        wakeTask?.cancel()
        wakeTask = nil
        retryTask?.cancel()
        retryTask = nil
        batteryTimer?.invalidate()
        batteryTimer = nil

        let oldSession = session
        session = nil
        handle?.onReport = nil
        handle?.onRemoved = nil
        handle?.close()
        handle = nil
        connecting = false
        attemptedDevices = []
        heldButtons = []

        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue as CFString
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        scanning = false

        Task { await oldSession?.close() }
        DeviceState.shared.connected = false
        print("[Mouser] Suspended HID session for system sleep")
    }

    /// Gives Bluetooth and IOHID a moment to settle before rediscovery.
    func resumeAfterWake(reconnect: Bool = true) {
        guard isSuspended else { return }
        isSuspended = false
        wakeTask?.cancel()
        guard reconnect else {
            wakeTask = nil
            print("[Mouser] HID reconnect deferred until Input Monitoring is granted")
            return
        }
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, !self.isSuspended else { return }
            self.start()
            self.wakeTask = nil
        }
        print("[Mouser] Scheduling HID reconnect after system wake")
    }

    private func deviceDisconnected() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        print("[Mouser] Disconnected")
        Task { await session?.close() }
        session = nil
        handle = nil
        divertedCIDs = []
        heldButtons = []
        attemptedDevices = []
        let state = DeviceState.shared
        state.connected = false
        state.deviceName = ""
        state.batteryLevel = nil
        state.batteryCharging = false
        state.dpi = nil
        state.wheelModeByte = nil
        if !isSuspended {
            scheduleRetryScan()
        }
    }

    // MARK: - Reads

    func refreshAll() async {
        await refreshBattery()
        await refreshDPI()
        await refreshSmartShift()
        await refreshWheelMode()
    }

    func refreshBattery() async {
        guard let session, let batteryIndex else { return }
        let function: UInt8 = batteryIsUnified ? 1 : 0
        guard let params = try? await session.request(feature: batteryIndex, function: function) else { return }
        applyBatteryParams(params)
    }

    private func applyBatteryParams(_ params: [UInt8]) {
        guard let level = params.first, level <= 100 else { return }
        let charging = params.count > 2 && (1...4).contains(params[2])
        print("[Mouser] Battery: \(level)%\(charging ? " (charging)" : "")")
        DeviceState.shared.batteryLevel = Int(level)
        DeviceState.shared.batteryCharging = charging
    }

    func refreshDPI() async {
        guard let session, let dpiIndex else { return }
        guard let params = try? await session.request(feature: dpiIndex, function: 2, params: [0x00]),
              params.count >= 3 else { return }
        DeviceState.shared.dpi = Int(params[1]) << 8 | Int(params[2])
        print("[Mouser] DPI: \(DeviceState.shared.dpi ?? 0)")
    }

    private func restorePreferredDPI() async {
        let config = ConfigStore.shared
        if let preferredDPI = config.preferredDPI {
            guard DeviceState.shared.dpi != preferredDPI else { return }
            _ = await setDPI(preferredDPI)
        } else if let deviceDPI = DeviceState.shared.dpi {
            config.preferredDPI = deviceDPI
        }
    }

    func refreshSmartShift() async {
        guard let session, let smartShiftIndex else { return }
        let readFunction: UInt8 = smartShiftEnhanced ? 1 : 0
        guard let params = try? await session.request(feature: smartShiftIndex, function: readFunction) else { return }
        let mode = params.first ?? 0
        let autoDisengage = params.count > 1 ? Int(params[1]) : 0
        let state = DeviceState.shared
        if mode == HIDPP.SmartShiftMode.freespin {
            state.smartShiftEnabled = false
        } else {
            state.smartShiftEnabled = HIDPP.SmartShiftMode.thresholdRange.contains(autoDisengage)
            if state.smartShiftEnabled { state.smartShiftThreshold = autoDisengage }
        }
    }

    func refreshWheelMode() async {
        guard let session, let wheelIndex else { return }
        guard let params = try? await session.request(feature: wheelIndex, function: 1) else { return }
        DeviceState.shared.wheelModeByte = params.first
    }

    // MARK: - Writes

    @discardableResult
    func setDPI(_ dpi: Int) async -> Bool {
        guard let session, let dpiIndex else { return false }
        let clamped = min(max(dpi, DeviceState.dpiRange.lowerBound), DeviceState.dpiRange.upperBound)
        let ok = (try? await session.request(feature: dpiIndex, function: 3,
                                             params: [0x00, UInt8(clamped >> 8), UInt8(clamped & 0xFF)])) != nil
        if ok {
            DeviceState.shared.dpi = clamped
            ConfigStore.shared.preferredDPI = clamped
        }
        return ok
    }

    @discardableResult
    func setSmartShift(enabled: Bool, threshold: Int) async -> Bool {
        guard let session, let smartShiftIndex else { return false }
        let writeFunction: UInt8 = smartShiftEnhanced ? 2 : 1
        let clamped = min(max(threshold, HIDPP.SmartShiftMode.thresholdRange.lowerBound),
                          HIDPP.SmartShiftMode.thresholdRange.upperBound)
        let params: [UInt8] = enabled
            ? [HIDPP.SmartShiftMode.ratchet, UInt8(clamped), 0x00]
            : [HIDPP.SmartShiftMode.ratchet, HIDPP.SmartShiftMode.disableThreshold, 0x00]
        let ok = (try? await session.request(feature: smartShiftIndex, function: writeFunction, params: params)) != nil
        if ok {
            DeviceState.shared.smartShiftEnabled = enabled
            DeviceState.shared.smartShiftThreshold = clamped
        }
        return ok
    }

    /// Read-modify-write of the 0x2121 wheel mode byte: only the invert bit (bit 2)
    /// is driven; target/resolution bits are preserved (see Mouser issue #244).
    @discardableResult
    func setWheelInvertVertical(_ invert: Bool) async -> Bool {
        guard let session, let wheelIndex else { return !invert }
        var mode = DeviceState.shared.wheelModeByte
        if mode == nil {
            guard let params = try? await session.request(feature: wheelIndex, function: 1) else { return false }
            mode = params.first
        }
        guard var byte = mode else { return false }
        byte &= ~(HIDPP.WheelModeBit.target | HIDPP.WheelModeBit.invert)
        if invert { byte |= HIDPP.WheelModeBit.invert }
        if byte != mode {
            guard (try? await session.request(feature: wheelIndex, function: 2, params: [byte])) != nil else { return false }
        }
        DeviceState.shared.wheelModeByte = byte
        return true
    }

    // MARK: - Button divert
    //
    // Mapped buttons are diverted at the firmware level: presses arrive as
    // HID++ divert events instead of OS events, so remapping works even while
    // Logi Options+ is also listening. Unmapped buttons get a *persistent*
    // undivert to undo whatever Options+ may have left on the device.

    func applyButtonConfiguration() async {
        guard let session, let reprogIndex else { return }
        for button in MouseButton.allCases {
            guard let cid = button.controlID else { continue }
            let mapped = ConfigStore.shared.action(for: button) != .default
            // Divert requires the persist bit (0x03) on this firmware — volatile-only
            // (0x01) acknowledges the write but never emits events (verified on device).
            let flags: UInt8 = mapped ? HIDPP.divertButtonFlags : HIDPP.undivertFlags
            let ok = (try? await session.request(feature: reprogIndex, function: 3,
                                                 params: [UInt8(cid >> 8), UInt8(cid & 0xFF), flags, 0x00, 0x00])) != nil
            if ok {
                if mapped { divertedCIDs.insert(cid) } else { 
                    divertedCIDs.remove(cid)
                    heldButtons.remove(cid)
                }
                print("[Mouser] \(mapped ? "Divert" : "Undivert") CID 0x\(String(cid, radix: 16)): OK")
            } else {
                print("[Mouser] \(mapped ? "Divert" : "Undivert") CID 0x\(String(cid, radix: 16)): FAILED")
            }
        }
    }

    /// Best-effort volatile cleanup on quit; power cycling the mouse also clears it.
    func undivertAll() async {
        guard let session, let reprogIndex else { return }
        for cid in divertedCIDs {
            _ = try? await session.request(feature: reprogIndex, function: 3,
                                           params: [UInt8(cid >> 8), UInt8(cid & 0xFF), HIDPP.undivertFlags, 0x00, 0x00])
        }
        divertedCIDs = []
        heldButtons = []
    }

    // MARK: - Unsolicited reports

    private func handleNotification(_ message: HIDPPMessage) {
        guard !isSuspended else { return }
        // Battery broadcast: event function 0, software ID != ours.
        if let batteryIndex, message.featureIndex == batteryIndex,
           message.function == 0, message.softwareID != HIDPP.softwareID {
            applyBatteryParams(message.params)
            return
        }
        // Diverted button event: params are pressed-CID pairs terminated by 0x0000.
        // This firmware emits them on function 2; older docs say function 0 — accept both.
        if let reprogIndex, message.featureIndex == reprogIndex,
           (message.function == 0 || message.function == 2) {
            var pressed = Set<UInt16>()
            var index = 0
            while index + 1 < message.params.count {
                let cid = UInt16(message.params[index]) << 8 | UInt16(message.params[index + 1])
                if cid == 0 { break }
                pressed.insert(cid)
                index += 2
            }
            handleDivertedButtons(pressed)
        }
    }

    private var heldButtons = Set<UInt16>()

    private func handleDivertedButtons(_ pressed: Set<UInt16>) {
        for button in MouseButton.allCases {
            guard let cid = button.controlID, divertedCIDs.contains(cid) else { continue }
            let now = pressed.contains(cid)
            let was = heldButtons.contains(cid)
            if now, !was {
                heldButtons.insert(cid)
                let action = ConfigStore.shared.action(for: button)
                print("[Mouser] Diverted press: \(button.rawValue) -> \(action.rawValue)")
                ActionPerformer.shared.perform(action)
            } else if !now, was {
                heldButtons.remove(cid)
            }
        }
    }
}

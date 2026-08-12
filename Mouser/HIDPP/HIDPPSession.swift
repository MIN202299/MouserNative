import Foundation

struct HIDPPMessage {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let function: UInt8
    let softwareID: UInt8
    let params: [UInt8]

    init?(reportID: UInt8, payload: [UInt8]) {
        guard reportID == HIDPP.longReportID || reportID == HIDPP.shortReportID,
              payload.count >= 3 else { return nil }
        deviceIndex = payload[0]
        featureIndex = payload[1]
        function = (payload[2] >> 4) & 0x0F
        softwareID = payload[2] & 0x0F
        params = Array(payload.dropFirst(3))
    }
}

/// Serial HID++ request/response exchange over one device handle.
/// All long-format (0x11) because BLE collections accept only long output reports.
actor HIDPPSession {
    typealias NotificationHandler = @Sendable (HIDPPMessage) -> Void

    private let device: HIDDeviceHandle
    private let notificationHandler: NotificationHandler
    private var pending: (feature: UInt8, function: UInt8, continuation: CheckedContinuation<[UInt8], Error>)?
    private var requestInFlight = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    init(device: HIDDeviceHandle, notificationHandler: @escaping NotificationHandler) {
        self.device = device
        self.notificationHandler = notificationHandler
        device.onReport = { [weak self] reportID, payload in
            guard let self, let message = HIDPPMessage(reportID: reportID, payload: payload) else { return }
            Task { await self.route(message) }
        }
    }

    @discardableResult
    func request(feature: UInt8, function: UInt8, params: [UInt8] = [], timeout: TimeInterval = 2.0) async throws -> [UInt8] {
        await acquireRequestSlot()
        defer { releaseRequestSlot() }
        return try await withCheckedThrowingContinuation { continuation in
            pending = (feature, function, continuation)
            var payload = [UInt8](repeating: 0, count: HIDPP.longPayloadLength)
            payload[0] = HIDPP.directDeviceIndex
            payload[1] = feature
            payload[2] = ((function & 0x0F) << 4) | HIDPP.softwareID
            for (index, byte) in params.prefix(HIDPP.longPayloadLength - 3).enumerated() {
                payload[3 + index] = byte
            }
            let written = device.write(reportID: HIDPP.longReportID, payload: payload)
            if !written {
                pending = nil
                continuation.resume(throwing: HIDPPError.notConnected)
                return
            }
            Task { [self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.expirePending(feature: feature)
            }
        }
    }

    private func acquireRequestSlot() async {
        if !requestInFlight {
            requestInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    private func releaseRequestSlot() {
        if requestWaiters.isEmpty {
            requestInFlight = false
        } else {
            let next = requestWaiters.removeFirst()
            next.resume()
        }
    }

    /// IRoot ping (getProtocolVersion). Used to probe candidates.
    func ping(timeout: TimeInterval = 0.4) async -> Bool {
        (try? await request(feature: 0x00, function: 1, params: [0, 0, 0], timeout: timeout)) != nil
    }

    /// IRoot getFeature: returns the feature index or nil when unsupported.
    func findFeature(_ featureID: UInt16, timeout: TimeInterval = 2.0) async -> UInt8? {
        guard let params = try? await request(
            feature: 0x00, function: 0,
            params: [UInt8(featureID >> 8), UInt8(featureID & 0xFF), 0x00],
            timeout: timeout
        ), let index = params.first, index != 0 else { return nil }
        return index
    }

    func close() {
        if let pending {
            self.pending = nil
            pending.continuation.resume(throwing: HIDPPError.notConnected)
        }
        device.close()
    }

    private func route(_ message: HIDPPMessage) {
        if message.featureIndex == 0xFF {
            if let pending {
                self.pending = nil
                pending.continuation.resume(throwing: HIDPPError.deviceError(message.params.count > 1 ? message.params[1] : 0))
            }
            return
        }
        if let pending, message.featureIndex == pending.feature,
           message.softwareID == HIDPP.softwareID,
           message.function == pending.function || message.function == (pending.function + 1) & 0x0F {
            self.pending = nil
            pending.continuation.resume(returning: message.params)
            return
        }
        notificationHandler(message)
    }

    private func expirePending(feature: UInt8) {
        guard let pending, pending.feature == feature else { return }
        print("[Mouser]   !! timeout feat=0x\(String(feature, radix: 16))")
        self.pending = nil
        pending.continuation.resume(throwing: HIDPPError.timeout)
    }
}

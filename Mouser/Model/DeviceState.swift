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
    /// Scroll wheel ratchet force in percent; nil when the firmware can't tune it.
    var ratchetTorque: Int?
    var defaultRatchetTorque: Int?
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

struct BatterySample: Codable, Equatable, Identifiable {
    var date: Date
    var level: Int
    var charging: Bool

    var id: Date { date }
}

/// Persists battery readings so the Battery pane can chart them. A sample is
/// kept when the level or charging state changes, or at most every 30 minutes
/// otherwise; anything older than 30 days is dropped.
@MainActor
@Observable
final class BatteryHistory {
    static let shared = BatteryHistory()

    static let retention: TimeInterval = 30 * 24 * 3600
    private static let heartbeat: TimeInterval = 30 * 60

    private(set) var samples: [BatterySample] = []
    private let fileURL: URL?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mouser", isDirectory: true)
        fileURL = dir?.appendingPathComponent("battery-history.json")
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([BatterySample].self, from: data) {
            samples = decoded.sorted { $0.date < $1.date }
        }
        prune(now: Date())
    }

    func record(level: Int, charging: Bool, at date: Date = Date()) {
        if let last = samples.last,
           last.level == level, last.charging == charging,
           date.timeIntervalSince(last.date) < Self.heartbeat {
            return
        }
        samples.append(BatterySample(date: date, level: level, charging: charging))
        prune(now: date)
        save()
    }

    func samples(since start: Date) -> [BatterySample] {
        samples.filter { $0.date >= start }
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        if let first = samples.first, first.date < cutoff {
            samples.removeAll { $0.date < cutoff }
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

import Foundation

/// UserDefaults-backed configuration. Observed by UI, consumed by the engine.
@MainActor
@Observable
final class ConfigStore {
    static let shared = ConfigStore()

    private let defaults = UserDefaults.standard
    private static let mappingsKey = "buttonMappings"

    var buttonMappings: [MouseButton: MouseAction] {
        didSet { saveMappings() }
    }

    var invertScrollVertical: Bool {
        didSet { defaults.set(invertScrollVertical, forKey: "invertScrollVertical") }
    }

    var showBatteryInMenuBar: Bool {
        didSet { defaults.set(showBatteryInMenuBar, forKey: "showBatteryInMenuBar") }
    }

    var notifyOnActionFailure: Bool {
        didSet { defaults.set(notifyOnActionFailure, forKey: "notifyOnActionFailure") }
    }

    private init() {
        if let data = defaults.data(forKey: Self.mappingsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var mappings: [MouseButton: MouseAction] = [:]
            for (key, value) in decoded {
                if let button = MouseButton(rawValue: key), let action = MouseAction(rawValue: value) {
                    mappings[button] = action
                }
            }
            buttonMappings = mappings
        } else {
            buttonMappings = [:]
        }
        invertScrollVertical = defaults.bool(forKey: "invertScrollVertical")
        showBatteryInMenuBar = defaults.object(forKey: "showBatteryInMenuBar") as? Bool ?? true
        notifyOnActionFailure = defaults.object(forKey: "notifyOnActionFailure") as? Bool ?? true
    }

    func action(for button: MouseButton) -> MouseAction {
        buttonMappings[button] ?? .default
    }

    func setAction(_ action: MouseAction, for button: MouseButton) {
        if action == .default {
            buttonMappings.removeValue(forKey: button)
        } else {
            buttonMappings[button] = action
        }
    }

    private func saveMappings() {
        let raw = Dictionary(uniqueKeysWithValues: buttonMappings.map { ($0.key.rawValue, $0.value.rawValue) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.mappingsKey)
        }
    }
}

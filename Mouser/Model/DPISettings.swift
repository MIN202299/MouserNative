import Foundation

struct DPIValueStore {
    private static let key = "preferredDPI"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var savedValue: Int? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return defaults.integer(forKey: Self.key)
    }

    func save(_ value: Int) {
        defaults.set(value, forKey: Self.key)
    }
}

struct DPISliderInteraction {
    private var draftValue: Double
    private var isEditing = false

    init(initialValue: Int) {
        draftValue = Double(initialValue)
    }

    var displayedValue: Int {
        Int(draftValue.rounded())
    }

    mutating func update(to value: Double) {
        draftValue = value
    }

    mutating func setEditing(_ editing: Bool) -> Int? {
        if editing {
            isEditing = true
            return nil
        }
        guard isEditing else { return nil }
        isEditing = false
        return displayedValue
    }

    mutating func syncFromDevice(_ value: Int) {
        guard !isEditing else { return }
        draftValue = Double(value)
    }
}

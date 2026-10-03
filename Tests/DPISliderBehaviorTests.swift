import Foundation

@main
struct DPISliderBehaviorTests {
    static func main() {
        testDPIValueSurvivesStoreRecreation()
        testDPIIsCommittedOnlyOnceWhenEditingEnds()
        testDeviceUpdatesDoNotInterruptDragging()
        print("DPI slider behavior tests passed")
    }

    private static func testDPIValueSurvivesStoreRecreation() {
        let suiteName = "com.duan.mouser.tests.dpi.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = DPIValueStore(defaults: defaults)
        precondition(firstStore.savedValue == nil)
        firstStore.save(2_750)

        let reopenedStore = DPIValueStore(defaults: defaults)
        precondition(reopenedStore.savedValue == 2_750, "Saved DPI was not restored")
    }

    private static func testDPIIsCommittedOnlyOnceWhenEditingEnds() {
        var interaction = DPISliderInteraction(initialValue: 1_000)

        precondition(interaction.setEditing(true) == nil)
        interaction.update(to: 2_400)
        precondition(interaction.displayedValue == 2_400)
        precondition(interaction.setEditing(false) == 2_400, "DPI should commit on release")
        precondition(interaction.setEditing(false) == nil, "DPI must not commit twice")
    }

    private static func testDeviceUpdatesDoNotInterruptDragging() {
        var interaction = DPISliderInteraction(initialValue: 1_000)

        _ = interaction.setEditing(true)
        interaction.update(to: 2_400)
        interaction.syncFromDevice(1_200)
        precondition(interaction.displayedValue == 2_400, "Device refresh interrupted dragging")

        _ = interaction.setEditing(false)
        interaction.syncFromDevice(1_200)
        precondition(interaction.displayedValue == 1_200)
    }
}

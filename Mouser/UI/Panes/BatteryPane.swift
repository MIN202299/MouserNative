import SwiftUI

struct BatteryPane: View {
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: deviceState.batteryIconName)
                        .font(.system(size: 44))
                        .foregroundStyle(batteryColor)
                        .frame(width: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        if let level = deviceState.batteryLevel {
                            Text("\(level)%")
                                .font(.largeTitle.bold())
                            Text(deviceState.batteryCharging
                                 ? String(localized: "Charging")
                                 : String(localized: "Discharging"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "No mouse connected"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: $config.showBatteryInMenuBar) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Show battery percentage in menu bar"))
                        Text(String(localized: "Display the charge level next to the menu bar icon."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Button(String(localized: "Refresh")) {
                        Task { await DeviceManager.shared.refreshBattery() }
                    }
                    .controlSize(.small)
                    .disabled(!deviceState.connected)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private var batteryColor: Color {
        guard let level = deviceState.batteryLevel else { return .secondary }
        if deviceState.batteryCharging { return .green }
        return level <= 20 ? .red : .primary
    }
}

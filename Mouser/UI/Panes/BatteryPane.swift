import SwiftUI

struct BatteryPane: View {
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(deviceState.batteryLevel ?? 0) / 100)
                            .stroke(batteryColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: deviceState.batteryCharging ? "bolt.fill" : "computermouse.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(deviceState.batteryLevel == nil ? Color.secondary : batteryColor)
                    }
                    .frame(width: 76, height: 76)
                    .animation(.easeOut(duration: 0.6), value: deviceState.batteryLevel)

                    VStack(alignment: .leading, spacing: 4) {
                        if let level = deviceState.batteryLevel {
                            Text("\(level)%")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Label(
                                deviceState.batteryCharging
                                    ? String(localized: "Charging")
                                    : String(localized: "Discharging"),
                                systemImage: deviceState.batteryIconName
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "No mouse connected"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await DeviceManager.shared.refreshBattery() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(String(localized: "Refresh"))
                    .buttonStyle(.borderless)
                    .disabled(!deviceState.connected)
                }
                .padding(.vertical, 8)
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
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private var batteryColor: Color {
        guard let level = deviceState.batteryLevel else { return .secondary }
        if deviceState.batteryCharging { return .green }
        switch level {
        case ...20: return .red
        case ...40: return .orange
        default: return .green
        }
    }
}

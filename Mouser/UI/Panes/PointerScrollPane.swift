import SwiftUI

struct PointerScrollPane: View {
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared
    @State private var dpiInteraction = DPISliderInteraction(initialValue: 1_000)

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "DPI"))
                        Spacer()
                        Text("\(dpiInteraction.displayedValue)")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    Slider(
                        value: dpiDraftBinding,
                        in: Double(DeviceState.dpiRange.lowerBound)...Double(DeviceState.dpiRange.upperBound),
                        step: 50,
                        label: { EmptyView() },
                        minimumValueLabel: {
                            Image(systemName: "tortoise")
                                .foregroundStyle(.secondary)
                        },
                        maximumValueLabel: {
                            Image(systemName: "hare")
                                .foregroundStyle(.secondary)
                        },
                        onEditingChanged: handleDPIEditingChanged
                    )
                    .labelsHidden()

                    HStack(spacing: 6) {
                        ForEach(Self.dpiPresets, id: \.self) { preset in
                            Button {
                                applyDPIPreset(preset)
                            } label: {
                                Text("\(preset)")
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(dpiInteraction.displayedValue == preset ? .accentColor : nil)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 4)
                .disabled(!deviceState.connected)
            } header: {
                Text("Pointer")
            }

            Section {
                Toggle(isOn: smartShiftBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "SmartShift"))
                        Text(String(localized: "Automatically switch between ratchet and free-spin scrolling."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!deviceState.connected || !deviceState.smartShiftSupported)

                if deviceState.smartShiftEnabled {
                    LabeledContent(String(localized: "Sensitivity")) {
                        HStack(spacing: 12) {
                            Slider(
                                value: thresholdBinding,
                                in: Double(HIDPP.SmartShiftMode.thresholdRange.lowerBound)...Double(HIDPP.SmartShiftMode.thresholdRange.upperBound),
                                step: 1
                            )
                            .frame(width: 160)
                            Text("\(deviceState.smartShiftThreshold)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                    .disabled(!deviceState.connected)
                }
            } header: {
                Text("Scroll Wheel")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear {
            if let preferredDPI = config.preferredDPI {
                dpiInteraction.syncFromDevice(preferredDPI)
            } else if let deviceDPI = deviceState.dpi {
                dpiInteraction.syncFromDevice(deviceDPI)
            }
        }
        .onChange(of: deviceState.dpi) { _, newValue in
            if let newValue {
                dpiInteraction.syncFromDevice(newValue)
            }
        }
    }

    private static let dpiPresets = [800, 1_200, 1_600, 2_400, 4_000]

    private func applyDPIPreset(_ preset: Int) {
        withAnimation { dpiInteraction.syncFromDevice(preset) }
        Task {
            let succeeded = await DeviceManager.shared.setDPI(preset)
            if !succeeded, let deviceDPI = deviceState.dpi {
                dpiInteraction.syncFromDevice(deviceDPI)
            }
        }
    }

    private var dpiDraftBinding: Binding<Double> {
        Binding(
            get: { Double(dpiInteraction.displayedValue) },
            set: { newValue in
                dpiInteraction.update(to: newValue)
            }
        )
    }

    private func handleDPIEditingChanged(_ isEditing: Bool) {
        guard let dpi = dpiInteraction.setEditing(isEditing) else { return }
        Task {
            let succeeded = await DeviceManager.shared.setDPI(dpi)
            if !succeeded, let deviceDPI = deviceState.dpi {
                dpiInteraction.syncFromDevice(deviceDPI)
            }
        }
    }

    private var smartShiftBinding: Binding<Bool> {
        Binding(
            get: { deviceState.smartShiftEnabled },
            set: { newValue in
                Task { await DeviceManager.shared.setSmartShift(enabled: newValue, threshold: deviceState.smartShiftThreshold) }
            }
        )
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(deviceState.smartShiftThreshold) },
            set: { newValue in
                Task { await DeviceManager.shared.setSmartShift(enabled: true, threshold: Int(newValue)) }
            }
        )
    }
}

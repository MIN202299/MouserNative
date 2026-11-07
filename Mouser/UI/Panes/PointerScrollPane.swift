import SwiftUI

struct PointerScrollPane: View {
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared
    @State private var dpiInteraction = DPISliderInteraction(initialValue: 1_000)
    @State private var torqueDraft: Double?

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
                                in: Double(HIDPP.SmartShiftMode.thresholdRange.lowerBound)...Double(HIDPP.SmartShiftMode.thresholdRange.upperBound)
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

                if let torque = deviceState.ratchetTorque {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Scroll Wheel Force"))
                                Text(String(localized: "How firmly the wheel clicks in ratchet mode."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(torqueDraft ?? Double(torque)))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if let defaultTorque = deviceState.defaultRatchetTorque, torque != defaultTorque {
                                Button {
                                    Task { await DeviceManager.shared.setRatchetTorque(defaultTorque) }
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Restore Defaults"))
                            }
                        }
                        Slider(
                            value: Binding(
                                get: { torqueDraft ?? Double(torque) },
                                set: { torqueDraft = $0.rounded() }
                            ),
                            in: Double(HIDPP.SmartShiftMode.torqueRange.lowerBound)...Double(HIDPP.SmartShiftMode.torqueRange.upperBound),
                            label: { EmptyView() },
                            minimumValueLabel: { Image(systemName: "dial.low").foregroundStyle(.secondary) },
                            maximumValueLabel: { Image(systemName: "dial.high").foregroundStyle(.secondary) },
                            onEditingChanged: { editing in
                                guard !editing, let draft = torqueDraft else { return }
                                Task {
                                    await DeviceManager.shared.setRatchetTorque(Int(draft))
                                    torqueDraft = nil
                                }
                            }
                        )
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
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
                // Snap to 50 here instead of `step:`, which draws tick dots.
                dpiInteraction.update(to: (newValue / 50).rounded() * 50)
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
                let threshold = Int(newValue.rounded())
                guard threshold != deviceState.smartShiftThreshold else { return }
                Task { await DeviceManager.shared.setSmartShift(enabled: true, threshold: threshold) }
            }
        )
    }
}

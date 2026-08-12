import SwiftUI

struct PointerScrollPane: View {
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "DPI")) {
                    HStack(spacing: 12) {
                        Slider(
                            value: dpiBinding,
                            in: Double(DeviceState.dpiRange.lowerBound)...Double(DeviceState.dpiRange.upperBound),
                            step: 50
                        )
                        .frame(width: 200)
                        Text("\(deviceState.dpi ?? 0)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
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

                Toggle(isOn: invertBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Invert scroll direction"))
                        Text(String(localized: "Written to the device firmware (read-modify-write, hi-res bit preserved)."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!deviceState.connected)
            } header: {
                Text("Scroll Wheel")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private var dpiBinding: Binding<Double> {
        Binding(
            get: { Double(deviceState.dpi ?? 1600) },
            set: { newValue in
                Task { await DeviceManager.shared.setDPI(Int(newValue)) }
            }
        )
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

    private var invertBinding: Binding<Bool> {
        Binding(
            get: { config.invertScrollVertical },
            set: { newValue in
                config.invertScrollVertical = newValue
                Task { await DeviceManager.shared.setWheelInvertVertical(newValue) }
            }
        )
    }
}

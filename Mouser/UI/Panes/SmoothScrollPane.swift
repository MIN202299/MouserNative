import AppKit
import SwiftUI

/// Scrolling options, matching Mos's "Scrolling" preferences one-to-one.
struct SmoothScrollPane: View {
    @State private var config = ConfigStore.shared
    @State private var permissions = PermissionManager.shared

    private var scroll: Binding<ScrollSettings> { $config.scroll }

    var body: some View {
        Form {
            Section {
                CheckboxRow(
                    label: String(localized: "Smooth Scrolling"),
                    title: String(localized: "Enable smooth scrolling"),
                    isOn: scroll.smooth
                ) {
                    Toggle(String(localized: "Smooth vertical scrolling"), isOn: scroll.smoothVertical)
                    Toggle(String(localized: "Smooth horizontal scrolling"), isOn: scroll.smoothHorizontal)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(String(localized: "Simulate trackpad (Beta)"), isOn: simulateTrackpad)
                        Text(String(localized: "May affect scrolling behavior."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                }
                .disabledDetail(!config.scroll.smooth)

                CheckboxRow(
                    label: String(localized: "Reverse Scrolling"),
                    title: String(localized: "Reverse wheel direction"),
                    isOn: scroll.reverse
                ) {
                    Toggle(String(localized: "Reverse vertical scrolling"), isOn: scroll.reverseVertical)
                    Toggle(String(localized: "Reverse horizontal scrolling"), isOn: scroll.reverseHorizontal)
                }
                .disabledDetail(!config.scroll.reverse)
            } footer: {
                if !permissions.accessibilityGranted {
                    Text("Requires Accessibility permission.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                HotkeyRow(
                    label: String(localized: "Accelerate Key"),
                    caption: String(localized: "Speeds up scrolling on long pages"),
                    hotkey: scroll.dash
                )
                HotkeyRow(
                    label: String(localized: "Toggle Key"),
                    caption: String(localized: "Hold to turn vertical scrolling into horizontal scrolling"),
                    hotkey: scroll.toggle
                )
                HotkeyRow(
                    label: String(localized: "Disable Key"),
                    caption: String(localized: "Hold to disable smooth scrolling"),
                    hotkey: scroll.block
                )
            }

            Section {
                ValueRow(
                    label: String(localized: "Minimum Step"),
                    caption: String(localized: "Controls the minimum distance of a single scroll"),
                    value: scroll.step,
                    range: ScrollSettings.stepRange
                )
                ValueRow(
                    label: String(localized: "Speed Gain"),
                    caption: String(localized: "Controls the tracking speed gain of continuous scrolling"),
                    value: scroll.speed,
                    range: ScrollSettings.speedRange
                )
                ValueRow(
                    label: String(localized: "Duration"),
                    caption: config.scroll.simulateTrackpad
                        ? String(localized: "Fixed while simulating a trackpad")
                        : String(localized: "Controls the easing duration of scrolling"),
                    value: scroll.duration,
                    range: ScrollSettings.durationRange
                )
                .disabled(config.scroll.simulateTrackpad)
            } footer: {
                HStack {
                    Spacer()
                    Button(String(localized: "Restore Defaults")) {
                        config.scroll = ScrollSettings()
                    }
                    .disabled(config.scroll == ScrollSettings())
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private var simulateTrackpad: Binding<Bool> {
        Binding(
            get: { config.scroll.simulateTrackpad },
            set: { config.scroll.setSimulateTrackpad($0) }
        )
    }
}

/// "Label   [✓] Title  (⋯)" with the ⋯ button opening a popover of sub-options.
private struct CheckboxRow<Detail: View>: View {
    let label: String
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder let detail: () -> Detail
    @State private var showingDetail = false
    @Environment(\.detailDisabled) private var detailDisabled

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Toggle(title, isOn: $isOn)
                    .toggleStyle(.checkbox)
                Button {
                    showingDetail.toggle()
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(detailDisabled)
                .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        detail()
                    }
                    .toggleStyle(.checkbox)
                    .padding(16)
                }
            }
        }
    }
}

private struct DetailDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var detailDisabled: Bool {
        get { self[DetailDisabledKey.self] }
        set { self[DetailDisabledKey.self] = newValue }
    }
}

private extension View {
    func disabledDetail(_ disabled: Bool) -> some View {
        environment(\.detailDisabled, disabled)
    }
}

/// A recorder for a scroll hotkey: click, then press a modifier key. ⓧ clears it.
private struct HotkeyRow: View {
    let label: String
    let caption: String
    @Binding var hotkey: ScrollModifier?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        recording ? stopRecording() : startRecording()
                    } label: {
                        Text(buttonTitle)
                            .foregroundStyle(hotkey == nil && !recording ? .secondary : .primary)
                            .frame(minWidth: 150, alignment: .leading)
                    }
                    .tint(recording ? .accentColor : nil)
                    .buttonStyle(.bordered)

                    Button {
                        stopRecording()
                        hotkey = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(hotkey == nil)
                    .help(String(localized: "Clear"))
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(label)
        }
        .onDisappear { stopRecording() }
    }

    private var buttonTitle: String {
        if recording { return String(localized: "Press a modifier key…") }
        return hotkey?.title ?? String(localized: "Not set")
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { stopRecording() } // Esc cancels
                return nil
            }
            if let modifier = ScrollModifier.pressed(in: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))) {
                hotkey = modifier
                stopRecording()
            }
            return event
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

/// "Label  ——●——  [ 33.60 ] ⇅" with a caption underneath, as in Mos.
private struct ValueRow: View {
    let label: String
    let caption: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Slider(value: clamped, in: range)
                        .frame(minWidth: 160)
                    TextField("", value: clamped, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                        .frame(width: 72)
                    Stepper("", value: clamped, in: range, step: 0.01)
                        .labelsHidden()
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(label)
        }
    }

    private var clamped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}

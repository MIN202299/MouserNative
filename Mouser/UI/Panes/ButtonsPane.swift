import SwiftUI

struct ButtonsPane: View {
    @State private var config = ConfigStore.shared
    @State private var deviceState = DeviceState.shared
    @State private var selectedButton: MouseButton?

    var body: some View {
        Form {
            Section {
                MouseDiagramView(selectedButton: $selectedButton)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 200
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                ForEach(MouseButton.allCases) { button in
                    LabeledContent {
                        ActionPickerButton(selection: binding(for: button))
                            .disabled(!deviceState.connected)
                    } label: {
                        Label {
                            Text(button.title)
                        } icon: {
                            Image(systemName: button.symbolName)
                                .foregroundStyle(selectedButton == button ? Color.accentColor : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("Button Assignments")
            } footer: {
                Text("Mappings are applied on the device via HID++ and stay active while Mouser runs. Power cycling the mouse restores defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private func binding(for button: MouseButton) -> Binding<MouseAction> {
        Binding(
            get: { config.action(for: button) },
            set: { newValue in
                config.setAction(newValue, for: button)
                Task { await DeviceManager.shared.applyButtonConfiguration() }
            }
        )
    }
}

/// Clickable MX Anywhere 3S diagram. Hotspot fractions come from the
/// Python Mouser device layout catalog (image is 239x400 pt).
private struct MouseDiagramView: View {
    @Binding var selectedButton: MouseButton?
    @State private var popoverButton: MouseButton?

    private let imageRatio: CGFloat = 239.0 / 400.0

    var body: some View {
        let height: CGFloat = 250
        let width = height * imageRatio

        ZStack {
            Image("MouseAnywhere3S")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)

            ForEach(MouseButton.allCases) { button in
                HotspotButton(
                    isSelected: selectedButton == button,
                    action: {
                        selectedButton = button
                        popoverButton = button
                    }
                )
                .position(
                    x: button.diagramPosition.x * width,
                    y: button.diagramPosition.y * height
                )
            }
        }
        .frame(width: width, height: height)
        .popover(item: $popoverButton) { popover in
            ButtonActionPopover(button: popover)
        }
    }
}

private struct HotspotButton: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isSelected ? 0.25 : 0))
                    .frame(width: 30, height: 30)
                Circle()
                    .fill(isSelected || hovering ? Color.accentColor : Color.black.opacity(0.35))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    }
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .scaleEffect(hovering ? 1.15 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

private extension MouseButton {
    var symbolName: String {
        switch self {
        case .middle: "circle.circle"
        case .back: "chevron.backward.circle"
        case .forward: "chevron.forward.circle"
        case .modeShift: "arrow.triangle.2.circlepath.circle"
        }
    }
}

private struct ButtonActionPopover: View {
    let button: MouseButton
    @State private var config = ConfigStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Label(button.title, systemImage: button.symbolName)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 14)
            ActionPickerList(selection: binding) {
                dismiss()
            }
        }
    }

    private var binding: Binding<MouseAction> {
        Binding(
            get: { config.action(for: button) },
            set: { newValue in
                config.setAction(newValue, for: button)
                Task { await DeviceManager.shared.applyButtonConfiguration() }
            }
        )
    }
}

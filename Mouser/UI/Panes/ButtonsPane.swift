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
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                ForEach(MouseButton.allCases) { button in
                    Picker(button.title, selection: binding(for: button)) {
                        ForEach(MouseAction.Category.allCases, id: \.self) { category in
                            Section(category.title) {
                                ForEach(MouseAction.allCases.filter { $0.category == category }) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!deviceState.connected)
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

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.25))
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                }
                .frame(width: 16, height: 16)
                .shadow(radius: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct ButtonActionPopover: View {
    let button: MouseButton
    @State private var config = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(button.title)
                .font(.headline)
            Picker(button.title, selection: binding) {
                ForEach(MouseAction.Category.allCases, id: \.self) { category in
                    Section(category.title) {
                        ForEach(MouseAction.allCases.filter { $0.category == category }) { action in
                            Text(action.title).tag(action)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(12)
        .frame(width: 240)
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

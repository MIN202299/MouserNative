import SwiftUI

struct GeneralPane: View {
    @State private var loginItems = LoginItemManager.shared
    @State private var permissions = PermissionManager.shared
    @State private var config = ConfigStore.shared
    @State private var conflictName: String?

    var body: some View {
        Form {
            if let conflictName {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Logitech software detected"))
                            Text(String(localized: "\(conflictName) is running and will fight Mouser for device access. Quit it to avoid conflicts."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Section {
                Toggle(isOn: launchAtLoginBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Launch at Login"))
                        Text(String(localized: "Start Mouser automatically when you sign in."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                LabeledContent(String(localized: "Accessibility")) {
                    HStack(spacing: 8) {
                        Label(
                            permissions.accessibilityGranted
                                ? String(localized: "Granted")
                                : String(localized: "Not granted"),
                            systemImage: permissions.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle"
                        )
                        .foregroundStyle(permissions.accessibilityGranted ? .green : .red)
                        .font(.subheadline)

                        if !permissions.accessibilityGranted {
                            Button(String(localized: "Open Settings…")) {
                                permissions.openSystemSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                Toggle(isOn: $config.notifyOnActionFailure) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Notify on action failure"))
                        Text(String(localized: "Show a system notification when a remapped action fails."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("System")
            }

            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mouser")
                            .font(.title2.bold())
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "A lightweight, fully local Logitech mouse remapper. No telemetry, no cloud, no Logitech account."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear {
            conflictName = OptionsPlusDetector.shared.conflictingAppName
            permissions.refresh()
            loginItems.refresh()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItems.enabled },
            set: { loginItems.setEnabled($0) }
        )
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}

import SwiftUI

struct MenuBarContentView: View {
    @State private var deviceState = DeviceState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if deviceState.connected {
                Label {
                    Text(deviceState.deviceName)
                } icon: {
                    Image("MouseAnywhere3S")
                }
                if let level = deviceState.batteryLevel {
                    let format = deviceState.batteryCharging
                        ? String(localized: "Battery: %d%% (charging)")
                        : String(localized: "Battery: %d%%")
                    Label(String(format: format, level), systemImage: deviceState.batteryIconName)
                }
            } else {
                Label(String(localized: "No mouse connected"), systemImage: "computermouse")
            }

            Divider()

            Button {
                SettingsWindowController.show()
            } label: {
                Text(String(localized: "Settings…"))
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text(String(localized: "Quit Mouser"))
            }
        }
    }
}

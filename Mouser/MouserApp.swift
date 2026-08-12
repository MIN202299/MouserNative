import SwiftUI

@main
struct MouserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "computermouse")
                if config.showBatteryInMenuBar, deviceState.connected, let level = deviceState.batteryLevel {
                    Text(verbatim: "\(level)%")
                }
            }
        }
    }
}

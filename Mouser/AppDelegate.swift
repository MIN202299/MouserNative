import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        NSApp.setActivationPolicy(.accessory)

        DeviceManager.shared.start()

        PermissionManager.shared.onAccessibilityGranted = {
            ButtonInterceptor.shared.start()
        }
        PermissionManager.shared.start()
        print("[Mouser] Accessibility granted: \(PermissionManager.shared.accessibilityGranted)")
        if PermissionManager.shared.accessibilityGranted {
            ButtonInterceptor.shared.start()
        }

        Notifier.shared.requestAuthorizationIfNeeded()

        if let conflict = OptionsPlusDetector.shared.conflictingAppName {
            Notifier.shared.notifyFailure(
                String(format: String(localized: "%@ is running and will fight Mouser for device access. Quit it to avoid conflicts."), conflict)
            )
        }

        if CommandLine.arguments.contains("-showSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindowController.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await DeviceManager.shared.undivertAll() }
    }
}

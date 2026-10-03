import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var powerLifecycleCoordinator: PowerLifecycleCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        NSApp.setActivationPolicy(.accessory)

        PermissionManager.shared.onAccessibilityGranted = {
            ButtonInterceptor.shared.start()
        }
        PermissionManager.shared.onInputMonitoringGranted = {
            DeviceManager.shared.start()
        }
        PermissionManager.shared.start()
        print("[Mouser] Accessibility granted: \(PermissionManager.shared.accessibilityGranted)")
        print("[Mouser] Input Monitoring granted: \(PermissionManager.shared.inputMonitoringGranted)")
        if PermissionManager.shared.accessibilityGranted {
            ButtonInterceptor.shared.start()
        }
        if PermissionManager.shared.inputMonitoringGranted {
            DeviceManager.shared.start()
        }

        powerLifecycleCoordinator = PowerLifecycleCoordinator(
            onSleep: {
                DeviceManager.shared.suspendForSleep()
                PermissionManager.shared.suspendForSleep()
            },
            onWake: {
                PermissionManager.shared.resumeAfterWake()
                DeviceManager.shared.resumeAfterWake(
                    reconnect: PermissionManager.shared.inputMonitoringGranted
                )
            }
        )
        powerLifecycleCoordinator?.start()

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
        powerLifecycleCoordinator?.stop()
        Task { await DeviceManager.shared.undivertAll() }
    }
}

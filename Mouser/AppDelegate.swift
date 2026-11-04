import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var powerLifecycleCoordinator: PowerLifecycleCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        NSApp.setActivationPolicy(.accessory)

        PermissionManager.shared.onAccessibilityGranted = {
            ButtonInterceptor.shared.start()
            ScrollEngine.shared.start()
        }
        PermissionManager.shared.onInputMonitoringGranted = {
            DeviceManager.shared.start()
        }
        PermissionManager.shared.start()
        print("[Mouser] Accessibility granted: \(PermissionManager.shared.accessibilityGranted)")
        print("[Mouser] Input Monitoring granted: \(PermissionManager.shared.inputMonitoringGranted)")
        if PermissionManager.shared.accessibilityGranted {
            ButtonInterceptor.shared.start()
            ScrollEngine.shared.start()
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

        #if DEBUG
        ScrollSelfTest.runIfRequested()
        #endif

        if CommandLine.arguments.contains("-previewPermissionGuide") {
            PermissionGuideController.shared.show(.accessibility, preview: true)
        } else if CommandLine.arguments.contains("-showOnboarding") {
            OnboardingWindowController.show()
        } else {
            OnboardingWindowController.showIfNeeded()
        }

        if CommandLine.arguments.contains("-showSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindowController.show()
            }
        }
    }

    /// Opening Mouser again while it is already running (Finder, Launchpad,
    /// Spotlight, Dock) brings its window back instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let permissions = PermissionManager.shared
        permissions.refresh()
        if permissions.accessibilityGranted && permissions.inputMonitoringGranted {
            SettingsWindowController.show()
        } else {
            OnboardingWindowController.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerLifecycleCoordinator?.stop()
        Task { await DeviceManager.shared.undivertAll() }
    }
}

import AppKit
import Foundation
import ServiceManagement
import UserNotifications

/// Detects a running Logi Options+ process, which fights us for HID++ access.
@MainActor
final class OptionsPlusDetector {
    static let shared = OptionsPlusDetector()

    private init() {}

    var conflictingAppName: String? {
        for app in NSWorkspace.shared.runningApplications {
            let bundleID = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let isLogitechOptions =
                (bundleID.hasPrefix("com.logi.") && (bundleID.contains("options") || name.contains("options")))
                || name.contains("logi options")
            if isLogitechOptions {
                return app.localizedName ?? "Logi Options+"
            }
        }
        return nil
    }
}

/// Launch-at-login via SMAppService.
@MainActor
@Observable
final class LoginItemManager {
    static let shared = LoginItemManager()

    private(set) var enabled = false

    private init() {
        refresh()
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Notifier.shared.notifyFailure(String(localized: "Login item update failed"))
        }
        refresh()
    }
}

/// System notifications for action failures.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var authorized = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    func notifyFailure(_ message: String) {
        guard ConfigStore.shared.notifyOnActionFailure else { return }
        let content = UNMutableNotificationContent()
        content.title = "Mouser"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

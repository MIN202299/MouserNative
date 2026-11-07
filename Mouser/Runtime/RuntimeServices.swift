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

/// System notifications for action failures and low battery.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var authorized = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
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

    func notifyLowBattery(_ alert: LowBatteryAlertTracker.Alert, deviceName: String) {
        guard ConfigStore.shared.lowBatteryAlertEnabled else { return }
        let device = deviceName.isEmpty ? String(localized: "Mouse") : deviceName
        let content = UNMutableNotificationContent()
        switch alert {
        case .low(let level):
            content.title = String(localized: "Low Mouse Battery")
            content.body = String(format: String(localized: "%@ is at %d%%. Charge it soon."), device, level)
        case .critical(let level):
            content.title = String(localized: "Mouse Battery Critically Low")
            content.body = String(format: String(localized: "%@ is at %d%%. Charge it now."), device, level)
        }
        content.sound = .default
        // A fixed identifier replaces the previous low-battery banner instead of stacking.
        let request = UNNotificationRequest(identifier: "lowBattery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

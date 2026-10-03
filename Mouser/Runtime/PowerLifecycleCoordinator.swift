import AppKit
import Foundation

/// Bridges workspace power notifications to app-owned suspend/resume work.
final class PowerLifecycleCoordinator {
    private let notificationCenter: NotificationCenter
    private let sleepNotifications: [Notification.Name]
    private let wakeNotifications: [Notification.Name]
    private let onSleep: () -> Void
    private let onWake: () -> Void
    private var observerTokens: [NSObjectProtocol] = []
    private var isSuspended = false

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        sleepNotifications: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ],
        wakeNotifications: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
        ],
        onSleep: @escaping () -> Void,
        onWake: @escaping () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.sleepNotifications = sleepNotifications
        self.wakeNotifications = wakeNotifications
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func start() {
        guard observerTokens.isEmpty else { return }
        observerTokens = sleepNotifications.map { notification in
            notificationCenter.addObserver(
                forName: notification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, !self.isSuspended else { return }
                self.isSuspended = true
                self.onSleep()
            }
        }
        observerTokens += wakeNotifications.map { notification in
            notificationCenter.addObserver(
                forName: notification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isSuspended else { return }
                self.isSuspended = false
                self.onWake()
            }
        }
    }

    func stop() {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
        observerTokens = []
    }

    deinit {
        stop()
    }
}

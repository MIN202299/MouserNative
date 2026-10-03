import Foundation

@main
struct PowerLifecycleCoordinatorTests {
    static func main() {
        let center = NotificationCenter()
        var sleepCount = 0
        var wakeCount = 0
        let displaySleepNotification = Notification.Name("MouserTestsDisplaySleep")
        let systemSleepNotification = Notification.Name("MouserTestsSystemSleep")
        let wakeNotification = Notification.Name("MouserTestsDisplayWake")

        let coordinator = PowerLifecycleCoordinator(
            notificationCenter: center,
            sleepNotifications: [displaySleepNotification, systemSleepNotification],
            wakeNotifications: [wakeNotification],
            onSleep: { sleepCount += 1 },
            onWake: { wakeCount += 1 }
        )

        coordinator.start()
        coordinator.start()
        center.post(name: displaySleepNotification, object: nil)
        center.post(name: systemSleepNotification, object: nil)
        center.post(name: displaySleepNotification, object: nil)
        precondition(sleepCount == 1, "Repeated sleep events must suspend services only once")
        precondition(wakeCount == 0)

        center.post(name: wakeNotification, object: nil)
        precondition(wakeCount == 1, "Wake notification must resume services once")

        coordinator.stop()
        center.post(name: displaySleepNotification, object: nil)
        center.post(name: wakeNotification, object: nil)
        precondition(sleepCount == 1, "Stopped coordinator must ignore sleep notifications")
        precondition(wakeCount == 1, "Stopped coordinator must ignore wake notifications")

        print("Power lifecycle coordinator tests passed")
    }
}

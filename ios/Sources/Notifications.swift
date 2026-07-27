import Foundation
import UserNotifications

/// Local notifications: rest-timer completion and the daily weigh-in
/// reminder. Foreground presentation stays suppressed — the in-app rest bar
/// and Live Activity already cover the visible cases.
enum LocalNotifications {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: rest timer

    static func scheduleRestDone(at date: Date, exercise: String, nextSet: Int) {
        cancelRestDone()
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "\(exercise) — set \(nextSet) is up"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "rest-done", content: content, trigger: trigger))
    }

    static func cancelRestDone() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["rest-done"])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["rest-done"])
    }

    // MARK: weigh-in reminder

    static func syncWeighInReminder(enabled: Bool, hour: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weigh-in"])
        guard enabled else { return }
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = "Weigh-in"
        content.body = "Hop on the scale and log it in Forge."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "weigh-in", content: content, trigger: trigger))
    }
}

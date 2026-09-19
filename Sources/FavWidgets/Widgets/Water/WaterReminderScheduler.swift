import Foundation
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Turns the water reminder settings into repeating local notifications
/// on this device. Re-run whenever the settings change or the widget is
/// opened, so a second device picks the schedule up too.
enum WaterReminderScheduler {
    static let identifierPrefix = "water-reminder-"
    static let notificationType = "water_reminder"

    /// Requests permission if it hasn't been asked, then replaces every
    /// pending water reminder with the current plan. Returns false when
    /// notifications are denied so the UI can say so.
    @discardableResult
    static func sync(_ log: WaterLog, quietHours: WidgetQuietHours? = nil) async -> Bool {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard log.reminders.enabled else { return true }

        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return false }

        for (index, minutes) in WaterReminderPlan.times(log.reminders, quietHours: quietHours).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Water"
            content.body = WaterReminderPlan.message(index: index, goalCups: log.goalCups)
            content.sound = .default
            content.threadIdentifier = "water"
            // The app registers this category with a "Log a cup" action
            // (WaterQuickLog.logCupAction) that writes the cup without opening.
            content.categoryIdentifier = WaterQuickLog.categoryIdentifier
            content.userInfo = ["type": notificationType]
            var date = DateComponents()
            date.hour = minutes / 60
            date.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(minutes)", content: content, trigger: trigger)
            try? await center.add(request)
        }
        return true
        #else
        return true
        #endif
    }
}

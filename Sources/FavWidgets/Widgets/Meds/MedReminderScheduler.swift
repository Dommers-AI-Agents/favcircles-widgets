import Foundation
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The med list as repeating local notifications on this phone. Unlike
/// Water, quiet hours don't silence these: a dose is a dose. Re-run on any
/// change and whenever the widget opens.
enum MedReminderScheduler {
    static let prefix = "med-"

    /// Replaces every pending med reminder. Returns false when
    /// notifications are denied, so the screen can say so.
    @discardableResult
    static func sync(_ settings: MedSettings) async -> Bool {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) && !$0.hasPrefix("med-snooze") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let plan = MedPlan.reminders(settings.meds)
        guard !plan.reminders.isEmpty else { return true }

        let current = await center.notificationSettings()
        var allowed = current.authorizationStatus == .authorized || current.authorizationStatus == .provisional
        if current.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return false }

        for r in plan.reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = "meds"
            // The app registers this category: "Took it" logs without opening
            content.categoryIdentifier = MedQuickLog.categoryIdentifier
            content.userInfo = ["type": MedQuickLog.notificationType, "medId": r.medId, "slot": r.minutes]
            var when = DateComponents()
            when.hour = r.minutes / 60
            when.minute = r.minutes % 60
            if let weekday = r.weekday { when.weekday = weekday }
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
        return true
        #else
        return true
        #endif
    }
}

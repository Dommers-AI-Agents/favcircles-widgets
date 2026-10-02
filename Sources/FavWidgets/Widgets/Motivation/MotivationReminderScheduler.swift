import Foundation
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules the coach's next few days of lines as one-off local
/// notifications (each with its own line). Re-run when a setting changes,
/// when "Did it" is tapped, whenever the widget opens, and by the app when
/// it comes to the foreground (so the rolling window never runs dry).
public enum MotivationReminderScheduler {
    static let identifierPrefix = "motivation-reminder-"
    public static let notificationType = "motivation_reminder"

    /// App launch / foreground / after a "Did it" action: re-plan from the
    /// saved document. Reminders off (maybe on another phone) clears this
    /// phone's; it never asks for permission unless they're on.
    public static func refresh(store: WidgetDataStore, quietHours: WidgetQuietHours? = nil) async {
        guard let log = await MotivationQuickLog.load(store: store) else { return }
        await sync(log, quietHours: quietHours)
    }

    @discardableResult
    public static func sync(_ log: MotivationLog, quietHours: WidgetQuietHours? = nil) async -> Bool {
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

        let calendar = Calendar.current
        for slot in MotivationPlan.slots(log, now: Date(), quietHours: quietHours, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "Coach Mane"
            content.body = slot.line
            content.sound = .default
            content.threadIdentifier = "motivation"
            // The app registers this category with a "Did it" action.
            content.categoryIdentifier = MotivationQuickLog.categoryIdentifier
            // lineId: "Send to someone 📣" opens on this exact line.
            content.userInfo = ["type": notificationType, "lineId": MotivationLines.id(for: slot.line)]
            var date = calendar.dateComponents([.year, .month, .day], from: slot.day.date(calendar: calendar))
            date.hour = slot.minutes / 60
            date.minute = slot.minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(slot.day.rawValue)-\(slot.minutes)", content: content, trigger: trigger)
            try? await center.add(request)
        }
        return true
        #else
        return true
        #endif
    }
}

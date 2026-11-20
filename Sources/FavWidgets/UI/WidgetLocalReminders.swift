import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// One-shot local reminders a widget derives from its document (Last Time
/// due days, Return Window last days). `replace` drops every pending request
/// with the prefix and schedules the new set, so a sync is idempotent and a
/// reinstall (WidgetRemindersRestore) rebuilds them.
enum WidgetLocalReminders {
    struct Item {
        let id: String
        let at: Date
        let title: String
        let body: String
        let type: String
    }

    static func replace(prefix: String, with items: [Item]) async {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard !items.isEmpty else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        for item in items where item.at > Date() {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = ["type": item.type]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.at)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        #endif
    }
}

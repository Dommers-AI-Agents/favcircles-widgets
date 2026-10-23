import Foundation
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Vet documents (photos of the pages or the PDF) and insurance cards: files
/// on this phone only (Application Support), never uploaded. The private
/// document keeps their file names so the screens know what to show.
enum DogLocalPhotos {
    static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FavWidgets", isDirectory: true).appendingPathComponent("Dogs", isDirectory: true)
    }

    /// Saves the file (a JPEG unless `ext` says otherwise) and returns its
    /// name, or nil when it couldn't be written.
    static func save(_ data: Data, prefix: String, ext: String = "jpg") -> String? {
        guard let folder else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(prefix)-\(UUID().uuidString.prefix(8)).\(ext)"
        do {
            #if os(iOS)
            try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            #endif
            return name
        } catch {
            return nil
        }
    }

    /// Saves a document's pages (JPEGs) or its PDF; nil when nothing could be written.
    static func saveDocument(title: String, pages: [Data] = [], pdf: Data? = nil) -> DogDocument? {
        if let pdf {
            return save(pdf, prefix: "dogs-doc", ext: "pdf").map { DogDocument(title: title, kind: .pdf, files: [$0]) }
        }
        let files = pages.compactMap { save($0, prefix: "dogs-doc") }
        return files.isEmpty ? nil : DogDocument(title: title, kind: .photos, files: files)
    }

    static func url(_ name: String) -> URL? { folder?.appendingPathComponent(name) }

    static func load(_ name: String) -> Data? {
        guard let url = folder?.appendingPathComponent(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func delete(_ name: String) {
        guard let url = folder?.appendingPathComponent(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Vaccine-due, birthday and gotcha-day notifications on this phone.
/// Re-run whenever the dogs or their records change, and on open.
enum DogReminderScheduler {
    @MainActor private static var lastSynced: [DogReminderPlan.Reminder]?

    @MainActor
    static func sync(dogs: [DogProfile], state: DogsState, quietHours: WidgetQuietHours?) async {
        let plan = DogReminderPlan.reminders(dogs: dogs, state: state, quietHours: quietHours)
        guard plan != lastSynced else { return }
        lastSynced = plan
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(DogReminderPlan.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard !plan.isEmpty else { return }
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return }
        for r in plan {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = "dogs"
            content.userInfo = ["type": "dog_reminder"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireAt)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        #endif
    }
}

import Foundation

/// "Did it 💪" from the coach's notification, with no widget on screen:
/// loads the motivation document, marks today done, saves with the
/// optimistic version, and retries once on a conflict. Returns the saved
/// log so the caller can re-plan today's remaining reminders.
public enum MotivationQuickLog {
    public static let categoryIdentifier = "MOTIVATION_REMINDER"
    public static let didItAction = "MOTIVATION_DID_IT"
    /// "Send to someone 📣": opens the app on the Motivation widget with the
    /// notification's line ready to send (the app registers it `.foreground`).
    public static let sendAction = "MOTIVATION_SEND"

    @discardableResult
    public static func markDone(store: WidgetDataStore, now: Date = Date(), calendar: Calendar = .current) async throws -> MotivationLog {
        var document = try await store.load(id: MotivationLog.documentId)
        for attempt in 0..<2 {
            var log = try document.map { try WidgetDocumentCodec.decode(MotivationLog.self, from: $0.payload) } ?? MotivationLog()
            log.setDone(true, on: DayKey(now, calendar: calendar))
            let next = WidgetDocument(version: document?.version ?? 0, payload: try WidgetDocumentCodec.encode(log), schemaVersion: MotivationLog.schemaVersion)
            do {
                _ = try await store.save(id: MotivationLog.documentId, document: next)
                return log
            } catch WidgetDataStoreError.conflict(let server) where attempt == 0 {
                if let server { document = server } else { document = try await store.load(id: MotivationLog.documentId) }
            }
        }
        throw WidgetDataStoreError.conflict(server: nil)
    }

    /// The saved log, for re-planning on app launch. Nil when there is none.
    public static func load(store: WidgetDataStore) async -> MotivationLog? {
        guard let document = try? await store.load(id: MotivationLog.documentId) else { return nil }
        return try? WidgetDocumentCodec.decode(MotivationLog.self, from: document.payload)
    }
}

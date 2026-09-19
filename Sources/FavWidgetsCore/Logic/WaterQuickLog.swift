import Foundation

/// "Log a cup" from the reminder itself. Runs in the app's notification
/// action handler, with no widget on screen: loads the water document,
/// adds a cup to today, saves with the optimistic version, and retries once
/// on a conflict by re-applying the cup to the server's copy.
public enum WaterQuickLog {
    /// The notification category the water reminders carry, and its action.
    public static let categoryIdentifier = "WATER_REMINDER"
    public static let logCupAction = "WATER_LOG_CUP"

    public struct Result: Equatable, Sendable {
        public let cups: Int
        public let goal: Int
    }

    @discardableResult
    public static func logCup(store: WidgetDataStore, now: Date = Date(), calendar: Calendar = .current) async throws -> Result {
        var document = try await store.load(id: WaterLog.documentId)
        for attempt in 0..<2 {
            var log = try document.map { try WidgetDocumentCodec.decode(WaterLog.self, from: $0.payload) } ?? WaterLog()
            let today = DayKey(now, calendar: calendar)
            log.add(1, on: today, calendar: calendar)
            let next = WidgetDocument(version: document?.version ?? 0, payload: try WidgetDocumentCodec.encode(log), schemaVersion: WaterLog.schemaVersion)
            do {
                _ = try await store.save(id: WaterLog.documentId, document: next)
                return Result(cups: log.cups(on: today), goal: log.goalCups)
            } catch WidgetDataStoreError.conflict(let server) where attempt == 0 {
                if let server { document = server } else { document = try await store.load(id: WaterLog.documentId) }
            }
        }
        throw WidgetDataStoreError.conflict(server: nil)
    }
}

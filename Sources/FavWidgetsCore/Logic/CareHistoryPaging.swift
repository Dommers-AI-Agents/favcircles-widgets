import Foundation

/// Paging back through a check-in's answers.
public enum CareHistoryPaging {
    /// The server's askedAt spelling ("2026-09-30T12:30:00.000Z"): the page
    /// cursor is compared as text, so it must match exactly.
    public static func cursor(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Older answers after the loaded ones, newest first, each ask once
    public static func append(_ older: [CareAsk], to loaded: [CareAsk]) -> [CareAsk] {
        var seen = Set(loaded.map(\.id))
        return loaded + older.filter { seen.insert($0.id).inserted }
    }
}

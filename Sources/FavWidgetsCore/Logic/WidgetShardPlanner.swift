import Foundation

/// Maps a widget + date to document ids. Retention is solved by sharding,
/// never by deleting: entry-style widgets get one document per month, so
/// years of history stay under the per-document cap.
public enum WidgetShardPlanner {
    public static func shardId(widgetId: String, month: MonthKey) -> String {
        "\(widgetId)_\(month.rawValue)"
    }

    public static func shardId(widgetId: String, day: DayKey) -> String {
        shardId(widgetId: widgetId, month: day.monthKey)
    }

    /// Documents to fetch at tab open for one widget: its settings document
    /// plus, for monthly widgets, the current and previous month (the
    /// previous month keeps streaks and "last workout" right on the 1st).
    public static func hotIds(for descriptor: FavWidgetDescriptor, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        switch descriptor.storage {
        case .single:
            return [descriptor.id]
        case .monthly:
            let current = MonthKey(now, calendar: calendar)
            return [descriptor.id,
                    shardId(widgetId: descriptor.id, month: current),
                    shardId(widgetId: descriptor.id, month: current.previous)]
        }
    }

    /// The hot set for a whole tab, preferences included.
    public static func hotIds(for descriptors: [FavWidgetDescriptor], now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var ids = [WidgetPreferences.documentId]
        for descriptor in descriptors {
            ids.append(contentsOf: hotIds(for: descriptor, now: now, calendar: calendar))
        }
        return ids
    }

    /// Parses `<widgetId>_<yyyy-MM>` back into its month; nil for settings ids.
    public static func month(fromShardId id: String) -> MonthKey? {
        guard let underscore = id.lastIndex(of: "_") else { return nil }
        let suffix = String(id[id.index(after: underscore)...])
        guard suffix.count == 7, suffix.dropFirst(4).first == "-",
              Int(suffix.prefix(4)) != nil, Int(suffix.suffix(2)) != nil else { return nil }
        return MonthKey(rawValue: suffix)
    }
}

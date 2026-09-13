import Foundation

/// A bar the widget suggested and the user accepted ("Let's go").
public struct NextBarVisit: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var placeId: String
    public var name: String
    public var source: WidgetPlaceSource
    public var savedByName: String?
    public var savers: [String]?
    public var distanceMeters: Double
    public var date: Date

    public init(id: UUID = UUID(), placeId: String, name: String, source: WidgetPlaceSource, savedByName: String?, savers: [String]? = nil, distanceMeters: Double, date: Date = Date()) {
        self.id = id
        self.placeId = placeId
        self.name = name
        self.source = source
        self.savedByName = savedByName
        self.savers = savers
        self.distanceMeters = distanceMeters
        self.date = date
    }
}

/// Tonight's suggestion, pinned to the day it was made so the card doesn't
/// re-roll on every render.
public struct NextBarPick: Codable, Equatable, Sendable {
    public var day: DayKey
    public var placeId: String
    public var name: String
    public var source: WidgetPlaceSource
    public var savedByName: String?
    public var savers: [String]?
    public var distanceMeters: Double

    public init(day: DayKey, placeId: String, name: String, source: WidgetPlaceSource, savedByName: String?, savers: [String]? = nil, distanceMeters: Double) {
        self.day = day
        self.placeId = placeId
        self.name = name
        self.source = source
        self.savedByName = savedByName
        self.savers = savers
        self.distanceMeters = distanceMeters
    }
}

/// Single document (`nextbar`): preferences, tonight's pick, a short
/// "recently suggested" ring for variety, and the full visit history.
public struct NextBarSettings: WidgetModel {
    public var maxDistanceMeters: Double
    public var sources: Set<WidgetPlaceSource>
    public var currentPick: NextBarPick?
    /// Most recent suggestions, newest last; capped because it only exists
    /// to avoid repeats (the visit history below is never trimmed).
    public var recentPickIds: [String]
    public var visits: [NextBarVisit]

    public static let recentLimit = 8

    public init(maxDistanceMeters: Double = 5_000, sources: Set<WidgetPlaceSource> = Set(WidgetPlaceSource.allCases),
                currentPick: NextBarPick? = nil, recentPickIds: [String] = [], visits: [NextBarVisit] = []) {
        self.maxDistanceMeters = maxDistanceMeters
        self.sources = sources
        self.currentPick = currentPick
        self.recentPickIds = recentPickIds
        self.visits = visits
    }

    public static let empty = NextBarSettings()

    public mutating func notePick(_ pick: NextBarPick) {
        currentPick = pick
        recentPickIds.removeAll { $0 == pick.placeId }
        recentPickIds.append(pick.placeId)
        if recentPickIds.count > Self.recentLimit {
            recentPickIds.removeFirst(recentPickIds.count - Self.recentLimit)
        }
    }

    public static func merge(local: NextBarSettings, remote: NextBarSettings) -> NextBarSettings {
        var merged = local
        let known = Set(local.visits.map(\.id))
        merged.visits.append(contentsOf: remote.visits.filter { !known.contains($0.id) })
        merged.visits.sort { $0.date < $1.date }
        return merged
    }
}

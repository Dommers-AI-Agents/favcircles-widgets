import Foundation

/// A run someone is sharing (Map My Run, 2026-10-06): live while they run —
/// watchers see the route, the pace, a ping every mile and can cheer — then
/// finished, kept for everyone who watched. As the server sends it.
public struct SharedRun: Decodable, Identifiable, Equatable, Sendable {
    public struct Watcher: Decodable, Equatable, Hashable, Sendable { public let id: String; public let name: String }
    public struct Cheer: Decodable, Equatable, Hashable, Sendable {
        public let fromId: String
        public let fromName: String
        public let emoji: String
        public let at: String
    }
    public struct Position: Decodable, Equatable, Sendable { public let lat: Double; public let lng: Double }

    public let id: String
    public let ownerId: String
    public let ownerName: String
    public let ownerAvatarUrl: String?
    public let isMine: Bool
    public let status: String            // live | finished
    public let unit: String              // mi | km
    public let startedAt: String?
    public let finishedAt: String?
    public let updatedAt: String?
    public let isPaused: Bool
    public let distanceM: Double
    public let movingSec: Double
    public let movingAsOf: String?
    public let splits: [Double]
    public let route: String
    public let position: Position?
    public let calories: Int?
    public let watchers: [Watcher]
    public let invitedCount: Int
    public let cheers: [Cheer]
    public let shareUrl: String
    public let postedAt: String?
    public let watching: Bool

    public var isLive: Bool { status == "live" }
    public var runUnit: RunUnit { unit == "km" ? .kilometers : .miles }
    public var coordinates: [(Double, Double)] { RunGeo.decode(route) }
}

public enum RunShare {
    /// Watchers see the runner's clock keep going between updates (it's the
    /// moving time as of the last update, plus the time since, unless paused).
    public static func movingSeconds(_ run: SharedRun, now: Date, parse: (String) -> Date? = RunShare.parseDate) -> Double {
        guard run.isLive, !run.isPaused, let asOf = run.movingAsOf.flatMap(parse) else { return run.movingSec }
        // A stale update (runner's phone lost signal) stops ticking after 2 min
        let gap = now.timeIntervalSince(asOf)
        return run.movingSec + max(0, min(gap, 120))
    }

    /// "Wes is running · 2.31 mi" / "Wes finished 5.02 mi"
    public static func headline(_ run: SharedRun) -> String {
        let d = RunMath.distanceText(run.distanceM, unit: run.runUnit)
        if run.isLive { return run.isPaused ? "\(run.ownerName) paused · \(d) \(run.unit)" : "\(run.ownerName) is running · \(d) \(run.unit)" }
        return "\(run.ownerName) ran \(d) \(run.unit)"
    }

    /// New cheers since the ones already shown (by sender + time).
    public static func newCheers(_ cheers: [SharedRun.Cheer], seen: Set<String>) -> [SharedRun.Cheer] {
        cheers.filter { !seen.contains(key($0)) }
    }
    public static func key(_ cheer: SharedRun.Cheer) -> String { "\(cheer.fromId)|\(cheer.at)" }

    public static let cheerEmojis = ["🔥", "👏", "💪", "🎉", "🏃", "❤️"]

    public static func parseDate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}

import Foundation

/// The run in progress, saved on this phone so it survives the app being
/// closed or killed mid-run (Wes, 2026-10-30: "make FavRun persistent like
/// the workout"). Reopening the app picks the run back up: the clock kept
/// going, GPS starts again, and the stretch the app missed joins the route
/// as a straight line from the last point. Finish or Discard deletes it.
/// Local only: a GPS run belongs to the phone that's running it.
public struct RunCheckpoint: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// An older one is a run someone forgot about, not one to resume.
    public static let maxAge: TimeInterval = 12 * 60 * 60

    public var version: Int
    public var userId: String
    public var track: RunTrack
    public var unit: RunUnit
    public var coachOn: Bool
    public var coachIntensity: MotivationIntensity
    public var coachedSplits: Int
    /// The run's id for the server, so live watching carries on as the same run
    public var clientKey: String
    public var liveRunId: String?
    public var savedAt: Date

    public init(userId: String, track: RunTrack, unit: RunUnit, coachOn: Bool, coachIntensity: MotivationIntensity,
                coachedSplits: Int, clientKey: String, liveRunId: String?, savedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.userId = userId; self.track = track; self.unit = unit; self.coachOn = coachOn
        self.coachIntensity = coachIntensity; self.coachedSplits = coachedSplits
        self.clientKey = clientKey; self.liveRunId = liveRunId; self.savedAt = savedAt
    }

    /// Worth resuming: this person's, this format, and recent.
    public func isResumable(for userId: String, now: Date = Date()) -> Bool {
        version == Self.currentVersion && self.userId == userId && now.timeIntervalSince(savedAt) <= Self.maxAge
    }
}

/// Where the checkpoint lives: one file per signed-in person in Application
/// Support (never iCloud-backed caches, never shared between accounts).
public struct RunCheckpointFile: Sendable {
    public let url: URL

    public init(userId: String, directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FavWidgets", isDirectory: true)
        let safe = userId.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        url = base.appendingPathComponent("run-in-progress-\(safe).json")
    }

    public func save(_ checkpoint: RunCheckpoint) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(checkpoint).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The saved run if it's still worth resuming; a stale or unreadable one is deleted.
    public func loadResumable(for userId: String, now: Date = Date()) -> RunCheckpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let checkpoint = try? decoder.decode(RunCheckpoint.self, from: data),
              checkpoint.isResumable(for: userId, now: now) else {
            clear()
            return nil
        }
        return checkpoint
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

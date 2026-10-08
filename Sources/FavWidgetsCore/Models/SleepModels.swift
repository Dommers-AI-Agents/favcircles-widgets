import Foundation

/// Sleep Score (Wes, 2026-10-08): last night from Apple Health (or logged by
/// hand), scored 0–100, with trends. Settings are one document; nights are
/// sharded by month (`sleep_YYYY-MM`) and never pruned.
public struct SleepSettings: WidgetModel {
    public static let schemaVersion = 1
    public var goalHours: Double
    /// Minutes after midnight (can be > 24*60 for after-midnight bedtimes); nil = none
    public var targetBedtime: Int?
    /// The person said yes to Apple Health once (we still re-check access)
    public var healthConnected: Bool
    public init(goalHours: Double = 8, targetBedtime: Int? = nil, healthConnected: Bool = false) {
        self.goalHours = goalHours; self.targetBedtime = targetBedtime; self.healthConnected = healthConnected
    }
    public static let empty = SleepSettings()
}

public enum SleepSource: String, Codable, Sendable { case health, manual }

/// One night, keyed by the day you woke up.
public struct SleepNight: Codable, Equatable, Identifiable, Sendable {
    public var day: DayKey
    public var bedtime: Date
    public var wakeTime: Date
    /// Minutes actually asleep (all stages); for manual nights = time in bed
    public var asleepMinutes: Int
    public var awakeMinutes: Int
    /// Stage minutes when the source has them (Apple Watch); nil otherwise
    public var deepMinutes: Int?
    public var remMinutes: Int?
    public var coreMinutes: Int?
    public var source: SleepSource
    /// How it felt, 1–5 (manual), optional
    public var feeling: Int?

    public var id: String { day.rawValue }
    public var inBedMinutes: Int { max(1, Int(wakeTime.timeIntervalSince(bedtime) / 60)) }
    public var hasStages: Bool { deepMinutes != nil && remMinutes != nil }

    public init(day: DayKey, bedtime: Date, wakeTime: Date, asleepMinutes: Int, awakeMinutes: Int = 0,
                deepMinutes: Int? = nil, remMinutes: Int? = nil, coreMinutes: Int? = nil,
                source: SleepSource, feeling: Int? = nil) {
        self.day = day; self.bedtime = bedtime; self.wakeTime = wakeTime; self.asleepMinutes = asleepMinutes
        self.awakeMinutes = awakeMinutes; self.deepMinutes = deepMinutes; self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes; self.source = source; self.feeling = feeling
    }
}

public struct SleepMonth: WidgetModel {
    public var nights: [SleepNight]
    public init(nights: [SleepNight] = []) { self.nights = nights }
    public static let empty = SleepMonth()

    /// One night per day. A manual night stays put; Health refreshes its own.
    public mutating func upsert(_ night: SleepNight) {
        if let i = nights.firstIndex(where: { $0.day == night.day }) {
            if nights[i].source == .manual && night.source == .health { return }
            nights[i] = night
        } else {
            nights.append(night)
        }
        nights.sort { $0.day < $1.day }
    }

    public static func merge(local: SleepMonth, remote: SleepMonth) -> SleepMonth {
        var merged = remote
        for n in local.nights { merged.upsert(n) }
        return merged
    }
}

/// One Apple Health sleep sample, already reduced to what we need.
public struct SleepSample: Equatable, Sendable {
    public enum Stage: Equatable, Sendable { case inBed, awake, core, deep, rem, asleep }
    public let start: Date
    public let end: Date
    public let stage: Stage
    public init(start: Date, end: Date, stage: Stage) { self.start = start; self.end = end; self.stage = stage }
}

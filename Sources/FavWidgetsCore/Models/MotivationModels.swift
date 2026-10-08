import Foundation

/// How hard the coach goes. Clean is the default; Savage is ruder (never swears) and has to
/// be picked on purpose.
public enum MotivationIntensity: String, Codable, CaseIterable, Sendable {
    case clean, savage

    public var title: String {
        switch self {
        case .clean: return "Tough love"
        case .savage: return "Savage"
        }
    }
}

/// What the coach yells about.
public enum MotivationFocus: String, Codable, CaseIterable, Sendable {
    case gym, run, discipline, legends

    public var title: String {
        switch self {
        case .gym: return "Gym"
        case .run: return "Running"
        case .discipline: return "No excuses"
        case .legends: return "Legends"
        }
    }
}

/// The Motivation widget's document: what kind of lines, when they ring, and
/// the days you told the coach you did it. Days are never pruned.
public struct MotivationLog: WidgetModel, Sendable {
    /// 2: the Legends focus (2026-10-07) — older packages can't decode it.
    /// 3: doneCounts (2026-10-08) — older packages would drop the counts on save.
    public static let schemaVersion = 3
    public static let documentId = "motivation"

    public var intensity: MotivationIntensity
    public var focus: [MotivationFocus]
    public var reminders: WaterReminders
    /// Days marked "Did it", as `DayKey.rawValue` (what the streak counts).
    public var doneDays: Set<String>
    /// How many times "Did it" was tapped each day: more than once a day is
    /// the point — the coach keeps pushing after the first (Wes, 2026-10-08).
    public var doneCounts: [String: Int]

    public init(
        intensity: MotivationIntensity = .clean,
        focus: [MotivationFocus] = MotivationFocus.allCases,
        reminders: WaterReminders = WaterReminders(enabled: false, intervalHours: 4, startMinutes: 7 * 60, endMinutes: 19 * 60),
        doneDays: Set<String> = [],
        doneCounts: [String: Int] = [:]
    ) {
        self.intensity = intensity
        self.focus = focus
        self.reminders = reminders
        self.doneDays = doneDays
        self.doneCounts = doneCounts
    }

    public static var empty: MotivationLog { MotivationLog() }

    enum CodingKeys: String, CodingKey { case intensity, focus, reminders, doneDays, doneCounts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MotivationLog()
        intensity = (try? c.decodeIfPresent(MotivationIntensity.self, forKey: .intensity)) ?? fallback.intensity
        // Unknown values (a newer section) are skipped, not the whole list
        let known = ((try? c.decodeIfPresent([String].self, forKey: .focus)) ?? nil)?.compactMap(MotivationFocus.init(rawValue:))
        focus = (known?.isEmpty == false ? known : nil) ?? fallback.focus
        reminders = try c.decodeIfPresent(WaterReminders.self, forKey: .reminders) ?? fallback.reminders
        doneDays = try c.decodeIfPresent(Set<String>.self, forKey: .doneDays) ?? []
        doneCounts = (try? c.decodeIfPresent([String: Int].self, forKey: .doneCounts)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(focus, forKey: .focus)
        try c.encode(reminders, forKey: .reminders)
        // Sorted so the bytes are stable across saves.
        try c.encode(doneDays.sorted(), forKey: .doneDays)
        try c.encode(doneCounts, forKey: .doneCounts)
    }

    /// Settings: last write wins. Done days: union, so two phones never lose one.
    public static func merge(local: MotivationLog, remote: MotivationLog) -> MotivationLog {
        var merged = local
        merged.doneDays.formUnion(remote.doneDays)
        // Per day, the higher count (two phones never undercount)
        merged.doneCounts.merge(remote.doneCounts) { max($0, $1) }
        return merged
    }

    public func isDone(_ day: DayKey) -> Bool { doneDays.contains(day.rawValue) }

    public mutating func setDone(_ done: Bool, on day: DayKey) {
        if done { doneDays.insert(day.rawValue) } else { doneDays.remove(day.rawValue); doneCounts[day.rawValue] = nil }
    }

    /// Times "Did it" was tapped on `day` (a day marked before counts existed is 1).
    public func doneCount(on day: DayKey) -> Int {
        max(doneCounts[day.rawValue] ?? 0, isDone(day) ? 1 : 0)
    }

    /// One more "Did it" today: counts it, and the day joins the streak.
    public mutating func logDidIt(on day: DayKey) {
        doneCounts[day.rawValue] = doneCount(on: day) + 1
        doneDays.insert(day.rawValue)
    }

    /// Takes back the last "Did it" of `day`; at zero the day leaves the streak.
    public mutating func undoDidIt(on day: DayKey) {
        let next = doneCount(on: day) - 1
        if next > 0 { doneCounts[day.rawValue] = next } else { setDone(false, on: day) }
    }

    /// Consecutive done days ending today (or yesterday, if today isn't done yet).
    public func streak(endingOn today: DayKey, calendar: Calendar = .current) -> Int {
        var day = isDone(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while isDone(day) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }
}

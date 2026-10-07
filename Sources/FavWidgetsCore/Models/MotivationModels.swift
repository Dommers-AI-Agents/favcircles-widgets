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
    public static let schemaVersion = 2
    public static let documentId = "motivation"

    public var intensity: MotivationIntensity
    public var focus: [MotivationFocus]
    public var reminders: WaterReminders
    /// Days marked "Did it", as `DayKey.rawValue`.
    public var doneDays: Set<String>

    public init(
        intensity: MotivationIntensity = .clean,
        focus: [MotivationFocus] = MotivationFocus.allCases,
        reminders: WaterReminders = WaterReminders(enabled: false, intervalHours: 4, startMinutes: 7 * 60, endMinutes: 19 * 60),
        doneDays: Set<String> = []
    ) {
        self.intensity = intensity
        self.focus = focus
        self.reminders = reminders
        self.doneDays = doneDays
    }

    public static var empty: MotivationLog { MotivationLog() }

    enum CodingKeys: String, CodingKey { case intensity, focus, reminders, doneDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MotivationLog()
        intensity = (try? c.decodeIfPresent(MotivationIntensity.self, forKey: .intensity)) ?? fallback.intensity
        // Unknown values (a newer section) are skipped, not the whole list
        let known = ((try? c.decodeIfPresent([String].self, forKey: .focus)) ?? nil)?.compactMap(MotivationFocus.init(rawValue:))
        focus = (known?.isEmpty == false ? known : nil) ?? fallback.focus
        reminders = try c.decodeIfPresent(WaterReminders.self, forKey: .reminders) ?? fallback.reminders
        doneDays = try c.decodeIfPresent(Set<String>.self, forKey: .doneDays) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(focus, forKey: .focus)
        try c.encode(reminders, forKey: .reminders)
        // Sorted so the bytes are stable across saves.
        try c.encode(doneDays.sorted(), forKey: .doneDays)
    }

    /// Settings: last write wins. Done days: union, so two phones never lose one.
    public static func merge(local: MotivationLog, remote: MotivationLog) -> MotivationLog {
        var merged = local
        merged.doneDays.formUnion(remote.doneDays)
        return merged
    }

    public func isDone(_ day: DayKey) -> Bool { doneDays.contains(day.rawValue) }

    public mutating func setDone(_ done: Bool, on day: DayKey) {
        if done { doneDays.insert(day.rawValue) } else { doneDays.remove(day.rawValue) }
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

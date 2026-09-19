import Foundation

/// Single document for all time. Each month is an array of cup counts
/// indexed by day-of-month (0-based), so a year is ~1 KB.
public struct WaterLog: WidgetModel {
    public var goalCups: Int
    public var cupMl: Int
    public var months: [MonthKey: [Int]]
    /// "Remind me every N hours" — synced with the document, scheduled as
    /// local notifications on each device that opens the widget.
    public var reminders: WaterReminders

    public init(goalCups: Int = 8, cupMl: Int = 250, months: [MonthKey: [Int]] = [:], reminders: WaterReminders = WaterReminders()) {
        self.goalCups = goalCups
        self.cupMl = cupMl
        self.months = months
        self.reminders = reminders
    }

    private enum CodingKeys: String, CodingKey { case goalCups, cupMl, months, reminders }

    /// Documents written before reminders existed decode with them off.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalCups = try c.decodeIfPresent(Int.self, forKey: .goalCups) ?? 8
        cupMl = try c.decodeIfPresent(Int.self, forKey: .cupMl) ?? 250
        months = try c.decodeIfPresent([MonthKey: [Int]].self, forKey: .months) ?? [:]
        reminders = try c.decodeIfPresent(WaterReminders.self, forKey: .reminders) ?? WaterReminders()
    }

    public static let empty = WaterLog()

    public func cups(on day: DayKey) -> Int {
        guard let counts = months[day.monthKey], day.day - 1 < counts.count, day.day >= 1 else { return 0 }
        return counts[day.day - 1]
    }

    public mutating func setCups(_ cups: Int, on day: DayKey, calendar: Calendar = .current) {
        let month = day.monthKey
        var counts = months[month] ?? Array(repeating: 0, count: month.dayCount(calendar: calendar))
        let needed = max(counts.count, day.day)
        if counts.count < needed { counts.append(contentsOf: Array(repeating: 0, count: needed - counts.count)) }
        counts[day.day - 1] = max(0, cups)
        months[month] = counts
    }

    public mutating func add(_ delta: Int, on day: DayKey, calendar: Calendar = .current) {
        setCups(cups(on: day) + delta, on: day, calendar: calendar)
    }

    /// Consecutive days (ending today or yesterday) that hit the goal.
    public func streak(endingOn today: DayKey, calendar: Calendar = .current) -> Int {
        var day = today
        var count = 0
        if cups(on: day) < goalCups { day = day.adding(days: -1, calendar: calendar) }
        while cups(on: day) >= goalCups {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
            if count > 3660 { break }
        }
        return count
    }

    /// Two devices both logging: a day's count is whichever is higher.
    public static func merge(local: WaterLog, remote: WaterLog) -> WaterLog {
        var merged = local
        for (month, remoteCounts) in remote.months {
            var counts = merged.months[month] ?? []
            if counts.count < remoteCounts.count {
                counts.append(contentsOf: Array(repeating: 0, count: remoteCounts.count - counts.count))
            }
            for (index, value) in remoteCounts.enumerated() {
                counts[index] = max(counts[index], value)
            }
            merged.months[month] = counts
        }
        return merged
    }
}


/// Reminder settings: on/off, every N hours, between a start and end time
/// (minutes since local midnight).
public struct WaterReminders: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var intervalHours: Int
    public var startMinutes: Int
    public var endMinutes: Int

    public init(enabled: Bool = false, intervalHours: Int = 2, startMinutes: Int = 8 * 60, endMinutes: Int = 21 * 60) {
        self.enabled = enabled
        self.intervalHours = intervalHours
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public static let intervalChoices = [1, 2, 3, 4]
}

/// When the reminders fire. Pure, so the schedule can be checked on a Mac.
public enum WaterReminderPlan {
    /// Minutes-of-day for each reminder: start, start + N h, … up to and
    /// including the end time. A window shorter than the interval yields
    /// just the start. iOS allows 64 pending local notifications; a 1-hour
    /// interval over 24 h is 24, well inside that.
    public static func times(_ reminders: WaterReminders) -> [Int] {
        let interval = max(1, reminders.intervalHours) * 60
        let start = max(0, min(23 * 60 + 59, reminders.startMinutes))
        let end = max(start, min(23 * 60 + 59, reminders.endMinutes))
        var out: [Int] = []
        var t = start
        while t <= end && out.count < 24 {
            out.append(t)
            t += interval
        }
        return out
    }

    /// "Every 2 hours, 8:00 AM – 9:00 PM · 7 reminders"
    public static func summary(_ reminders: WaterReminders, locale: Locale = .current) -> String {
        guard reminders.enabled else { return "Off" }
        let n = times(reminders).count
        let every = reminders.intervalHours == 1 ? "Every hour" : "Every \(reminders.intervalHours) hours"
        return "\(every), \(clock(reminders.startMinutes, locale: locale)) – \(clock(reminders.endMinutes, locale: locale)) · \(n) reminder\(n == 1 ? "" : "s")"
    }

    /// The notification's line. Varies a little so it doesn't read as spam.
    public static func message(index: Int, goalCups: Int) -> String {
        let lines = [
            "Time for a glass of water 💧",
            "Sip break — a cup now keeps the streak going",
            "Water check: have a glass",
            "Another cup gets you closer to \(goalCups) today"
        ]
        return lines[max(0, index) % lines.count]
    }

    public static func clock(_ minutes: Int, locale: Locale = .current) -> String {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps) else { return "\(minutes / 60):\(String(format: "%02d", minutes % 60))" }
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

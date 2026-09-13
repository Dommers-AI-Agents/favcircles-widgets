import Foundation

/// Single document for all time. Each month is an array of cup counts
/// indexed by day-of-month (0-based), so a year is ~1 KB.
public struct WaterLog: WidgetModel {
    public var goalCups: Int
    public var cupMl: Int
    public var months: [MonthKey: [Int]]

    public init(goalCups: Int = 8, cupMl: Int = 250, months: [MonthKey: [Int]] = [:]) {
        self.goalCups = goalCups
        self.cupMl = cupMl
        self.months = months
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

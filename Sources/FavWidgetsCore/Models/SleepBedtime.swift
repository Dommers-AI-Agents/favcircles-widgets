import Foundation

/// Bedtime for Sleep Sounds (Wes, 2026-11-05: "turn on automatically at a
/// specified time on weekdays"). iOS won't let an app start sound on its own
/// at a set time, so Bedtime is a reminder at that time with a Play button,
/// and a "Play Sleep Sounds" action the Shortcuts app can run on a schedule
/// with no tap at all.
public struct SleepBedtime: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Minutes after midnight (22:00 = 1320)
    public var minutes: Int
    /// Calendar weekdays it applies to: 1 = Sunday … 7 = Saturday
    public var weekdays: [Int]
    /// The saved or built-in mix to play; nil = whatever played last
    public var mixId: String?

    public init(enabled: Bool = false, minutes: Int = 22 * 60, weekdays: [Int] = SleepBedtime.weekdaysOnly, mixId: String? = nil) {
        self.enabled = enabled
        self.minutes = minutes
        self.weekdays = weekdays
        self.mixId = mixId
    }

    /// Sunday through Thursday nights: the nights before a weekday
    public static let weeknights = [1, 2, 3, 4, 5]
    public static let weekdaysOnly = [2, 3, 4, 5, 6]
    public static let everyDay = [1, 2, 3, 4, 5, 6, 7]
}

public enum SleepBedtimePlan {
    /// One repeating trigger per chosen day: (weekday, hour, minute)
    public static func triggers(_ bedtime: SleepBedtime) -> [DateComponents] {
        guard bedtime.enabled else { return [] }
        return Set(bedtime.weekdays.filter { (1...7).contains($0) }).sorted().map { day in
            var components = DateComponents()
            components.weekday = day
            components.hour = bedtime.minutes / 60
            components.minute = bedtime.minutes % 60
            return components
        }
    }

    /// The mix bedtime plays: its chosen one if it still exists, else the last played
    public static func mix(for bedtime: SleepBedtime?, in settings: SleepSoundsSettings) -> (levels: [String: Double], name: String) {
        if let id = bedtime?.mixId,
           let mix = (settings.mixes + SleepMix.builtIns).first(where: { $0.id == id }) {
            return (mix.levels, mix.name)
        }
        return (settings.startingLevels, settings.startingName)
    }

    /// "Weeknights", "Weekdays", "Every night", or "Mon, Wed, Fri"
    public static func daysLabel(_ weekdays: [Int], calendar: Calendar = .current) -> String {
        let days = Set(weekdays.filter { (1...7).contains($0) })
        if days == Set(SleepBedtime.everyDay) { return "Every night" }
        if days == Set(SleepBedtime.weekdaysOnly) { return "Weekdays" }
        if days == Set(SleepBedtime.weeknights) { return "Sunday to Thursday" }
        if days.isEmpty { return "No days" }
        let symbols = calendar.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    public static func reminderTitle() -> String { "Time to wind down" }

    public static func reminderBody(mixName: String) -> String { "Tap Play to start \(mixName)." }
}

/// The words on the Bedtime screen and the Shortcuts guide
public enum SleepBedtimeCopy {
    /// "10:00 PM" (12-hour, as the Clock app shows it here)
    public static func time(_ minutes: Int) -> String {
        let hour = minutes / 60, minute = minutes % 60
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
    }

    /// The Shortcuts automation, step by step, with this bedtime filled in
    public static func steps(_ bedtime: SleepBedtime) -> [String] {
        [
            "Open the Shortcuts app and tap Automation at the bottom.",
            "Tap + (or New Automation), then choose Time of Day.",
            "Set \(time(bedtime.minutes)), choose Weekly, and pick \(SleepBedtimePlan.daysLabel(bedtime.weekdays).lowercased() == "weekdays" ? "Monday to Friday" : SleepBedtimePlan.daysLabel(bedtime.weekdays)).",
            "Choose Run Immediately (not After Confirmation), then tap Next.",
            "Search for FavCircles and pick Play Sleep Sounds. Tap Done."
        ]
    }
}

import Foundation

/// The three ways widgets say "when". Each was written once per widget;
/// they read differently on purpose (a mailing day looks forward, a
/// workout looks back, a reading wants the time of day), so all three
/// live here under names that say which is which.
public enum WidgetDateCopy {
    /// Looking forward: "today", "tomorrow", "Monday", then "Mon, Oct 5".
    public static func futureDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 99
        return days < 7 ? formatted(date, template: "EEEE", calendar: calendar) : formatted(date, template: "EEE MMM d", calendar: calendar)
    }

    /// Looking back: "today", "yesterday", "3 days ago", "2 weeks ago", then "Sat 5 Oct".
    public static func pastDay(_ date: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<0: return "later"
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return formatted(date, template: "EEE d MMM", calendar: calendar)
        }
    }

    /// A moment: "9:02 AM" today, "yesterday 7:10 PM", or "Sep 12".
    public static func dayTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        if calendar.isDate(date, inSameDayAs: now) {
            f.timeStyle = .short; f.dateStyle = .none
            return f.string(from: date).plainSpaces
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            f.timeStyle = .short; f.dateStyle = .none
            return "yesterday " + f.string(from: date).plainSpaces
        }
        return formatted(date, template: "MMM d", calendar: calendar)
    }

    /// A date in a localized template, e.g. "MMM d" → "Sep 12".
    public static func formatted(_ date: Date, template: String, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }
}

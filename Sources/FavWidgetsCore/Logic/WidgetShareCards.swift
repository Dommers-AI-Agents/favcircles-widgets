import Foundation

/// Each widget's own share card (Wes, 2026-10-09: "yes" to the next batch).
/// Minimal, says what was shared, nothing private: Stocks shares the market
/// indexes, never the user's own list.
public extension WidgetShareCardContent {
    static func water(cups: Int, goal: Int, streak: Int) -> WidgetShareCardContent {
        let reached = cups >= goal && goal > 0
        return WidgetShareCardContent(
            headline: reached ? "Hit my water goal" : "\(cups) of \(goal) cups today",
            detail: reached ? "\(cups) cups today" : nil,
            stats: [.init("\(cups)", cups == 1 ? "cup" : "cups"), .init("\(goal)", "goal")]
                + (streak > 1 ? [.init("\(streak)", "day streak")] : []),
            linkTitle: reached ? "Hit my water goal 💧" : "\(cups) of \(goal) cups today 💧")
    }

    static func habits(done: Int, due: Int, bestStreak: Int) -> WidgetShareCardContent {
        let headline = due == 0 ? "Keeping my habits" : done >= due ? "All \(due) habits done today" : "\(done) of \(due) habits done today"
        return WidgetShareCardContent(
            headline: headline,
            stats: (due > 0 ? [.init("\(done)/\(due)", "today")] : []) + (bestStreak > 0 ? [.init("\(bestStreak)", "best streak")] : []),
            linkTitle: "\(headline) ✅")
    }

    /// Temperatures arrive formatted in the user's unit ("72°").
    static func weather(temp: String, condition: String?, high: String?, low: String?, place: String?) -> WidgetShareCardContent {
        let headline = [temp, condition].compactMap { $0 }.joined(separator: " · ")
        return WidgetShareCardContent(
            headline: headline,
            detail: place,
            stats: [high.map { .init($0, "high") }, low.map { .init($0, "low") }].compactMap { $0 },
            linkTitle: place.map { "\(headline) in \($0)" } ?? headline)
    }

    /// The market indexes' moves today: (name, percent change).
    static func markets(_ moves: [(name: String, percent: Double)]) -> WidgetShareCardContent {
        let text = { (p: Double) in String(format: "%@%.1f%%", p >= 0 ? "+" : "", p) }
        return WidgetShareCardContent(
            headline: "Markets today",
            stats: moves.prefix(4).map { .init(text($0.percent), $0.name) },
            linkTitle: moves.first.map { "\($0.name) \(text($0.percent)) today" } ?? "Markets today")
    }

    static func sleepSounds(mix: String, nightsThisMonth: Int) -> WidgetShareCardContent {
        WidgetShareCardContent(
            headline: "Falling asleep to \(mix)",
            stats: nightsThisMonth > 0 ? [.init("\(nightsThisMonth)", nightsThisMonth == 1 ? "night this month" : "nights this month")] : [],
            linkTitle: "Falling asleep to \(mix) 🌙")
    }

    /// Leads to the quote itself (the reel), not just the widget.
    static func quote(text: String, author: String?, url: URL?) -> WidgetShareCardContent {
        WidgetShareCardContent(
            headline: "A quote for today",
            detail: "“\(text)”" + (author.map { " — \($0)" } ?? ""),
            linkTitle: author.map { "“\(text)” — \($0)" } ?? "“\(text)”",
            url: url)
    }

    static func workout(name: String, startedAt: Date, minutes: Int, exercises: Int, sets: Int, cardioMinutes: Int,
                        calendar: Calendar = .current) -> WidgetShareCardContent {
        var stats: [Stat] = [.init("\(max(1, minutes))", "min")]
        if exercises > 0 { stats += [.init("\(exercises)", "exercises"), .init("\(sets)", "sets")] }
        if cardioMinutes > 0 { stats.append(.init("\(cardioMinutes)", "min cardio")) }
        return WidgetShareCardContent(headline: name, detail: dayText(startedAt, calendar: calendar), stats: stats,
                                      linkTitle: "\(name) · \(max(1, minutes)) min")
    }

    static func motivation(line: String, streak: Int) -> WidgetShareCardContent {
        WidgetShareCardContent(
            headline: "Coach Mane says",
            detail: line,
            stats: streak > 1 ? [.init("\(streak)", "day streak")] : [],
            linkTitle: "Coach Mane · FavCircles")
    }

    internal static func dayText(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}

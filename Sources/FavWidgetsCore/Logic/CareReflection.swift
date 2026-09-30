import Foundation

/// What the person being checked on sees about their OWN answers: the week
/// at a glance, how their 0–10 answers are moving, and the daily habits.
/// Until now the parent saw only today's question and one "last answer" line
/// while the family saw trends (Wes, 2026-09-30: "Does he see all of his
/// answers and a trend over time?"). Pure, so it is tested on the Mac.
/// Histories arrive newest-first, as the server sends them.
public enum CareReflection {

    /// One calendar day in the week strip.
    public struct Day: Equatable, Sendable {
        public var date: Date
        /// "M", "T", … for the strip.
        public var letter: String
        public var asked: Int
        public var answered: Int
        /// The day's latest mood answer, when one was given.
        public var mood: CareAnswer?
        public var isToday: Bool
    }

    /// The last `count` calendar days, oldest first, ending today. A question
    /// still open counts as asked but not as missed yet.
    public static func days(_ history: [CareAsk], now: Date = Date(), calendar: Calendar = .current, count: Int = 7) -> [Day] {
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEEE"
        return (0..<count).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let asks = history.filter { calendar.isDate($0.askedAt, inSameDayAs: date) && $0.pushDelivered }
            let mood = asks.first { ($0.kind == .mood || $0.kind == .unknown) && $0.isAnswered && $0.answer != nil }?.answer
            return Day(date: date, letter: formatter.string(from: date), asked: asks.count,
                       answered: asks.filter(\.isAnswered).count, mood: mood, isToday: back == 0)
        }
    }

    /// Days in a row, counting back from today, with at least one answer.
    /// Today not answered YET doesn't break it — the streak runs to yesterday.
    public static func streak(_ history: [CareAsk], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let answeredDays = Set(history.filter(\.isAnswered).map { calendar.startOfDay(for: $0.answeredAt ?? $0.askedAt) })
        var day = calendar.startOfDay(for: now)
        if !answeredDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while answeredDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// One 0–10 question over time: every answer in the window, oldest first.
    public struct Series: Equatable, Sendable {
        public var short: String
        public var lowLabel: String
        public var highLabel: String
        public var scores: [Int]
        public var latest: Int { scores.last ?? 0 }
        public var average: Double { scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count) }
        public var averageText: String { String(format: "%.1f", average) }
    }

    /// Scale answers per question within `days`, the most recently answered
    /// question first, each series oldest → newest (the chart's left → right).
    public static func scaleSeries(_ history: [CareAsk], now: Date = Date(), days: Int = 14) -> [Series] {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        var order: [String] = []
        var byShort: [String: (low: String, high: String, scores: [Int])] = [:]
        for ask in history where ask.kind == .scale && ask.isAnswered {
            guard let score = ask.answerScore, (ask.answeredAt ?? ask.askedAt) >= since else { continue }
            let key = ask.short ?? ask.questionText
            if byShort[key] == nil { order.append(key); byShort[key] = (ask.low ?? "0", ask.high ?? "10", []) }
            byShort[key]?.scores.append(score)
        }
        return order.compactMap { key in
            guard let entry = byShort[key] else { return nil }
            return Series(short: key, lowLabel: entry.low, highLabel: entry.high, scores: entry.scores.reversed())
        }
    }

    /// A daily task ("Did you take your medicine today?") and how often the
    /// answer was yes, among the times it was answered.
    public struct Habit: Equatable, Sendable {
        public var question: String
        public var yes: Int
        public var answered: Int
    }

    /// `done` questions only: their yes is always the good answer. (A yes/no
    /// like "Any dizziness?" can go either way, so it stays in the list.)
    public static func habits(_ history: [CareAsk], now: Date = Date(), days: Int = 7) -> [Habit] {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        var order: [String] = []
        var tallies: [String: (yes: Int, answered: Int)] = [:]
        for ask in history where ask.kind == .done && ask.isAnswered && ask.askedAt >= since {
            if tallies[ask.questionText] == nil { order.append(ask.questionText); tallies[ask.questionText] = (0, 0) }
            tallies[ask.questionText]?.answered += 1
            if ask.answerValue == "yes" { tallies[ask.questionText]?.yes += 1 }
        }
        return order.compactMap { question in
            tallies[question].map { Habit(question: question, yes: $0.yes, answered: $0.answered) }
        }
    }

    /// The line at the top of the week card — warm, never scolding.
    public static func weekHeadline(answered: Int, asked: Int, streak: Int) -> String {
        if asked == 0 { return "Your answers will show up here." }
        var line = "You answered \(answered) of \(asked) this week."
        if streak >= 2 { line += " \(streak) days in a row!" }
        return line
    }

    /// "Taken 5 of 6 days" style wording for a habit row.
    public static func habitLine(_ habit: Habit) -> String {
        habit.answered == 1 ? (habit.yes == 1 ? "Yes, the one time it was asked" : "Not the one time it was asked")
            : "Yes \(habit.yes) of \(habit.answered) times"
    }
}

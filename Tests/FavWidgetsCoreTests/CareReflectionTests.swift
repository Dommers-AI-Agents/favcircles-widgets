import Foundation
import Testing
@testable import FavWidgetsCore

/// The parent's own view of their answers (Sal's side of How Are You?).
struct CareReflectionTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    // Wednesday 2026-09-30, 20:00 New York
    private let now = Date(timeIntervalSince1970: 1_790_812_800)

    private func ask(_ id: String, kind: CareQuestionKind = .mood, question: String? = nil, short: String? = nil, daysAgo: Double,
                     status: String = "answered", answer: CareAnswer? = nil, value: String? = nil, score: Int? = nil,
                     delivered: Bool = true) -> CareAsk {
        let at = now.addingTimeInterval(-daysAgo * 86400)
        return CareAsk(askId: id, planId: "p", questionText: question ?? id, kind: kind, short: short, low: "No pain", high: "Worst pain",
                       askedAt: at, status: status, answer: answer, answerValue: value, answerScore: score,
                       answeredAt: status == "answered" ? at : nil, pushDelivered: delivered)
    }

    @Test func theWeekStripHasSevenDaysEndingTodayWithTheDaysMood() {
        let history = [
            ask("m0", daysAgo: 0.1, answer: .great),
            ask("d1", kind: .done, daysAgo: 1, value: "yes"),
            ask("m2", daysAgo: 2, status: "missed"),
            ask("m3", daysAgo: 3, answer: .notGreat),
            ask("x9", daysAgo: 9, answer: .okay) // before the strip
        ]
        let days = CareReflection.days(history, now: now, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.last?.isToday == true)
        #expect(days.map(\.letter) == ["T", "F", "S", "S", "M", "T", "W"])
        #expect(days[6].mood == .great)
        #expect(days[5].answered == 1 && days[5].mood == nil)   // a done answer, no mood
        #expect(days[4].asked == 1 && days[4].answered == 0)    // missed
        #expect(days[3].mood == .notGreat)
        #expect(days[0].asked == 0)
    }

    @Test func theStreakCountsBackAndForgivesTodayNotAnsweredYet() {
        let answeredTodayToo = [ask("a", daysAgo: 0.1), ask("b", daysAgo: 1), ask("c", daysAgo: 2), ask("d", daysAgo: 4)]
        #expect(CareReflection.streak(answeredTodayToo, now: now, calendar: calendar) == 3)
        let notYetToday = [ask("b", daysAgo: 1), ask("c", daysAgo: 2)]
        #expect(CareReflection.streak(notYetToday, now: now, calendar: calendar) == 2)
        #expect(CareReflection.streak([ask("old", daysAgo: 3)], now: now, calendar: calendar) == 0)
    }

    @Test func scaleSeriesRunOldestToNewestPerQuestion() {
        let history = [
            ask("p3", kind: .scale, short: "Pain", daysAgo: 0.2, score: 5),
            ask("s2", kind: .scale, short: "Sleep", daysAgo: 0.5, score: 8),
            ask("p2", kind: .scale, short: "Pain", daysAgo: 3, score: 1),
            ask("p1", kind: .scale, short: "Pain", daysAgo: 6, score: 3),
            ask("px", kind: .scale, short: "Pain", daysAgo: 20, score: 9),   // outside 14 days
            ask("pm", kind: .scale, short: "Pain", daysAgo: 1, status: "missed")
        ]
        let series = CareReflection.scaleSeries(history, now: now)
        #expect(series.map(\.short) == ["Pain", "Sleep"])
        #expect(series[0].scores == [3, 1, 5])
        #expect(series[0].latest == 5)
        #expect(series[0].averageText == "3.0")
        #expect(series[1].scores == [8])
    }

    @Test func habitsTallyDoneQuestionsOnly() {
        let meds = "Did you take your medicine today?"
        let history = [
            ask("h1", kind: .done, question: meds, daysAgo: 0.2, value: "yes"),
            ask("h2", kind: .done, question: meds, daysAgo: 1, value: "not_yet"),
            ask("h3", kind: .done, question: meds, daysAgo: 2, value: "yes"),
            ask("y1", kind: .yesno, question: "Any dizziness?", daysAgo: 1, value: "yes"),
            ask("h4", kind: .done, question: meds, daysAgo: 3, status: "missed")
        ]
        let habits = CareReflection.habits(history, now: now)
        #expect(habits == [CareReflection.Habit(question: meds, yes: 2, answered: 3)])
        #expect(CareReflection.habitLine(habits[0]) == "Yes 2 of 3 times")
    }

    @Test func theHeadlineIsWarm() {
        #expect(CareReflection.weekHeadline(answered: 0, asked: 0, streak: 0) == "Your answers will show up here.")
        #expect(CareReflection.weekHeadline(answered: 5, asked: 9, streak: 1) == "You answered 5 of 9 this week.")
        #expect(CareReflection.weekHeadline(answered: 5, asked: 9, streak: 3) == "You answered 5 of 9 this week. 3 days in a row!")
    }
}

import Foundation
import Testing
@testable import FavWidgetsCore

struct WidgetShareCardsTests {
    @Test func water() {
        #expect(WidgetShareCardContent.water(cups: 5, goal: 8, streak: 0).headline == "5 of 8 cups today")
        let hit = WidgetShareCardContent.water(cups: 9, goal: 8, streak: 4)
        #expect(hit.headline == "Hit my water goal")
        #expect(hit.stats.map(\.label) == ["cups", "goal", "day streak"])
    }

    @Test func habits() {
        #expect(WidgetShareCardContent.habits(done: 3, due: 4, bestStreak: 12).headline == "3 of 4 habits done today")
        #expect(WidgetShareCardContent.habits(done: 4, due: 4, bestStreak: 12).headline == "All 4 habits done today")
        #expect(WidgetShareCardContent.habits(done: 0, due: 0, bestStreak: 0).stats.isEmpty)
    }

    @Test func weatherAndMarkets() {
        let w = WidgetShareCardContent.weather(temp: "72°", condition: "Sunny", high: "78°", low: "60°", place: "Charlotte")
        #expect(w.headline == "72° · Sunny")
        #expect(w.linkTitle == "72° · Sunny in Charlotte")
        let m = WidgetShareCardContent.markets([("S&P 500", 0.42), ("Nasdaq", -1.234)])
        #expect(m.stats.map(\.value) == ["+0.4%", "-1.2%"])
        #expect(m.linkTitle == "S&P 500 +0.4% today")
    }

    @Test func quoteLeadsToTheQuote() {
        let url = URL(string: "https://api.favcircles.com/app/quote/ali-champion")!
        let q = WidgetShareCardContent.quote(text: "Don't quit.", author: "Muhammad Ali", url: url)
        #expect(q.detail == "“Don't quit.” — Muhammad Ali")
        #expect(WidgetShareCard.items(widgetId: "quotes", content: q, cardJPEG: Data([1])).count == 1)
        if case .link(let u, _, _) = WidgetShareCard.items(widgetId: "quotes", content: q, cardJPEG: Data([1]))[0] { #expect(u == url) }
    }

    @Test func workoutSleepMotivation() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = ISO8601DateFormatter().date(from: "2026-10-09T14:00:00Z")!
        let wk = WidgetShareCardContent.workout(name: "Chest and Back", startedAt: start, minutes: 62, exercises: 5, sets: 18, cardioMinutes: 0, calendar: cal)
        #expect(wk.detail == "Fri, Oct 9")
        #expect(wk.linkTitle == "Chest and Back · 62 min")
        #expect(WidgetShareCardContent.sleepSounds(mix: "Rain on a tent", nightsThisMonth: 1).stats.first?.label == "night this month")
        #expect(WidgetShareCardContent.motivation(line: "Go.", streak: 3).detail == "Go.")
    }
}

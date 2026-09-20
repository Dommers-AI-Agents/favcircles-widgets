import Testing
import Foundation
@testable import FavWidgets
@testable import FavWidgetsCore

@Suite("Daily quote")
struct QuotesTests {
    @Test func settingsDecodeWithSensibleDefaultsWhenTheServerIsTerse() throws {
        let response = try JSONDecoder().decode(QuoteSettingsResponse.self, from: Data("{}".utf8))
        #expect(response.prefs.enabled == false)
        #expect(response.prefs.time == "08:00")
        #expect(response.prefs.email == false)
        #expect(response.today == nil)
    }

    @Test func aDeliveredQuoteCarriesItsAttribution() throws {
        let json = """
        {"prefs":{"enabled":true,"categories":["calm"],"time":"21:30","email":true},
         "categories":[{"id":"calm","label":"Calm","blurb":"Slow down"}],
         "today":{"text":"Breathe.","author":"Thich Nhat Hanh","category":"calm"}}
        """
        let response = try JSONDecoder().decode(QuoteSettingsResponse.self, from: Data(json.utf8))
        #expect(response.prefs.time == "21:30")
        #expect(response.prefs.email)
        #expect(response.categories.first?.label == "Calm")
        #expect(response.today?.attribution == "— Thich Nhat Hanh")
    }

    @Test func anAnonymousQuoteHasNoDanglingDash() throws {
        let quote = DailyQuote(text: "Keep going.", author: nil)
        #expect(quote.attribution == nil)
        #expect(DailyQuote(text: "x", author: "").attribution == nil)
    }

    @Test func theTimeSurvivesTheRoundTripThroughThePicker() {
        let settings = QuoteSettings(times: ["21:05"])
        let asDate = settings.timeAsDate
        #expect(QuoteSettings.time(from: asDate) == "21:05")
        // Midnight is a real choice and must not become 12:00.
        #expect(QuoteSettings.time(from: QuoteSettings(times: ["00:00"]).timeAsDate) == "00:00")
    }

    @Test func theCardSpellsTheHourOutTheWayPeopleSayIt() {
        #expect(QuoteCopy.friendly("08:00") == "8:00 AM")
        #expect(QuoteCopy.friendly("00:30") == "12:30 AM")
        #expect(QuoteCopy.friendly("12:00") == "12:00 PM")
        #expect(QuoteCopy.friendly("21:05") == "9:05 PM")
    }

    @Test func theWidgetIsRegisteredAndKeepsItsId() async {
        let ids = await MainActor.run { FavWidgetRegistry.all.map(\.descriptor.id) }
        #expect(ids.contains("quotes"))
    }
}

struct QuoteTimesTests {
    @Test func decodesTimesWithFallbackToTheSingleTime() throws {
        let old = try WidgetJSON.decode(QuoteSettings.self, from: Data(#"{"enabled":true,"time":"07:15"}"#.utf8))
        #expect(old.times == ["07:15"])
        #expect(old.time == "07:15")
        let new = try WidgetJSON.decode(QuoteSettings.self, from: Data(#"{"enabled":true,"times":["08:00","13:00"],"time":"08:00"}"#.utf8))
        #expect(new.times == ["08:00", "13:00"])
    }

    @Test func scheduleCopyAndNextSlot() {
        #expect(QuoteCopy.schedule(["08:00"]) == "Your quote arrives at 8:00 AM")
        #expect(QuoteCopy.schedule(["08:00", "18:30"]) == "Your quotes arrive at 8:00 AM and 6:30 PM")
        #expect(QuoteCopy.schedule(["08:00", "13:00", "18:30"]) == "Your quotes arrive at 8:00 AM, 1:00 PM and 6:30 PM")
        #expect(QuoteCopy.nextSuggestedTime(after: ["08:00"]) == "13:00")
        #expect(QuoteCopy.nextSuggestedTime(after: ["08:00", "20:00"]) == "21:00")
        #expect(QuoteCopy.nextSuggestedTime(after: ["23:00"]) == "23:00")
    }
}

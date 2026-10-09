import Foundation
import Testing
@testable import FavWidgetsCore

/// Every widget has a share card (Wes, 2026-10-09).
struct WidgetShareCardContentTests {
    @Test func genericCardNamesTheWidget() {
        let d = FavWidgetDescriptor(id: "water", title: "Water", subtitle: "Track your water", symbolName: "drop.fill",
                                    accentHex: "#3182CE", category: .health, shareBlurb: "Track your water through the day.")
        let c = WidgetShareCardContent.generic(d)
        #expect(c.headline == "Water")
        #expect(c.detail == "Track your water through the day.")
        #expect(c.linkTitle == "Water · FavCircles")
        let items = WidgetShareCard.items(widgetId: "water", content: c, cardJPEG: Data([1]))
        guard items.count == 1, case .link(let url, let title, _) = items[0] else { Issue.record("not one link"); return }
        #expect(url.absoluteString == "https://api.favcircles.com/app/widget/water")
        #expect(title == "Water · FavCircles")
    }

    @Test func runCardShowsDistanceTimePace() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = ISO8601DateFormatter().date(from: "2026-10-09T11:38:00Z")!
        let run = RunRecord(startedAt: start, endedAt: start.addingTimeInterval(1400), movingSeconds: 1348,
                            distanceMeters: 2.28 * 1609.344, route: "", splitsMile: [], splitsKm: [], efforts: [:], calories: 250)
        let c = WidgetShareCardContent.run(run, unit: .miles, mapJPEG: nil, calendar: cal)
        #expect(c.headline == "2.28 mi run")
        #expect(c.detail == "Fri, Oct 9")
        #expect(c.stats.map(\.label) == ["mi", "time", "/mi"])
        #expect(c.linkTitle == "2.28 mi run · FavRun")
    }

    @Test func noCardFallsBackToText() {
        let c = WidgetShareCardContent(headline: "Water", detail: "Track it", linkTitle: "Water · FavCircles")
        let items = WidgetShareCard.items(widgetId: "water", content: c, cardJPEG: nil)
        guard items.count == 1, case .text(let t) = items[0] else { Issue.record("expected text"); return }
        #expect(t == "Water — Track it")
    }
}

import Testing
import Foundation
@testable import FavWidgetsCore

struct WidgetSearchMatcherTests {
    private let all = [
        FavWidgetDescriptor(id: "postcard", title: "Postcard", subtitle: "Send a postcard from anywhere", symbolName: "envelope", accentHex: "#000000", category: .social),
        FavWidgetDescriptor(id: "run", title: "FavRun", subtitle: "Track your runs on a map", symbolName: "figure.run", accentHex: "#000000", category: .fitness),
        FavWidgetDescriptor(id: "fridgemail", title: "Fridge Mail", subtitle: "Kids' drawings to grandparents", symbolName: "envelope", accentHex: "#000000", category: .social),
        FavWidgetDescriptor(id: "weather", title: "Weather", subtitle: "Right now, the next hours and 10 days", symbolName: "cloud", accentHex: "#000000", category: .health)
    ]

    @Test func titleMatchIgnoringCase() {
        #expect(WidgetSearchMatcher.matches("postcard", in: all).map(\.id) == ["postcard"])
        #expect(WidgetSearchMatcher.matches("POST", in: all).map(\.id) == ["postcard"])
        #expect(WidgetSearchMatcher.matches("fridgemail", in: all).map(\.id) == ["fridgemail"])
    }

    @Test func subtitleAndIdWordsForLongerQueries() {
        #expect(WidgetSearchMatcher.matches("run", in: all).map(\.id) == ["run"])        // title FavRun
        #expect(WidgetSearchMatcher.matches("track", in: all).map(\.id) == ["run"])      // subtitle word
        #expect(WidgetSearchMatcher.matches("ma", in: all).map(\.id) == ["fridgemail"])  // short: title only
    }

    @Test func titleHitsLeadAndLimit() {
        let hits = WidgetSearchMatcher.matches("mail", in: all)
        #expect(hits.first?.id == "fridgemail")
        #expect(WidgetSearchMatcher.matches("e", in: all, limit: 2).count == 2)
        #expect(WidgetSearchMatcher.matches("   ", in: all).isEmpty)
    }
}

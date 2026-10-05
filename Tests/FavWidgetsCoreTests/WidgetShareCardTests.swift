import Foundation
import Testing
@testable import FavWidgetsCore

/// One bubble per share (Wes, 2026-10-05).
struct WidgetShareCardTests {
    @Test func cardIsOneTappableLink() {
        let items = WidgetShareCard.items(widgetId: "motivation", title: "Coach Mane · FavCircles", cardJPEG: Data([1]), fallbackText: "line")
        #expect(items.count == 1)
        guard case .link(let url, let title, let jpeg) = items[0] else { Issue.record("not a link"); return }
        #expect(url.absoluteString == "https://api.favcircles.com/app/widget/motivation")
        #expect(title == "Coach Mane · FavCircles")
        #expect(jpeg == Data([1]))
    }

    @Test func noCardFallsBackToTextAlone() {
        let items = WidgetShareCard.items(widgetId: "drink", title: "t", cardJPEG: nil, fallbackText: "Paper Plane")
        guard items.count == 1, case .text(let text) = items[0] else { Issue.record("expected text"); return }
        #expect(text == "Paper Plane")
    }
}

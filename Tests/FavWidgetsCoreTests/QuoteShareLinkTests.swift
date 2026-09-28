import Testing
import Foundation
@testable import FavWidgetsCore

struct QuoteShareLinkTests {
    @Test func slugBecomesTheAppLink() {
        #expect(QuoteShareLink.url(quoteId: "angelou-rainbow")?.absoluteString
                == "https://api.favcircles.com/app/quote/angelou-rainbow")
    }

    @Test func idsThatCantSitInAPathGetNoLink() {
        #expect(QuoteShareLink.url(quoteId: "") == nil)
        #expect(QuoteShareLink.url(quoteId: "a/b") == nil)
        #expect(QuoteShareLink.url(quoteId: "a b") == nil)
    }

    @Test func sharesTheLinkAlone() {
        let quote = QuoteReelItem(id: "ashe-start", text: "Start where you are.", author: "Arthur Ashe")
        let items = QuoteShareLink.items(for: quote)
        #expect(items.count == 1)
        guard case .url(let url) = items.first else { Issue.record("expected a url"); return }
        #expect(url.absoluteString.hasSuffix("/app/quote/ashe-start"))
    }

    @Test func fallsBackToTextWithoutALink() {
        let quote = QuoteReelItem(id: "bad id", text: "Start where you are.", author: "Arthur Ashe")
        guard case .text(let line) = QuoteShareLink.items(for: quote).first else { Issue.record("expected text"); return }
        #expect(line == "Start where you are.\n— Arthur Ashe")
    }
}

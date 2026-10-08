import Testing
@testable import FavWidgetsCore

struct PostcardPriceCopyTests {
    @Test func aSpecialStrikesTheRegularPrice() {
        #expect(PostcardPriceCopy.was(priceCents: 199, regularPriceCents: 399) == "$3.99")
        #expect(PostcardPriceCopy.now(priceCents: 199) == "$1.99")
        #expect(PostcardPriceCopy.badge(priceCents: 199, regularPriceCents: 399, label: "Today only") == "$1.99 · Today only")
        #expect(PostcardPriceCopy.badge(priceCents: 199, regularPriceCents: 399, label: " ") == "$1.99 special")
    }

    @Test func noSpecialNoStrikeNoBadge() {
        #expect(PostcardPriceCopy.was(priceCents: 399, regularPriceCents: 399) == nil)
        #expect(PostcardPriceCopy.was(priceCents: 399, regularPriceCents: nil) == nil)
        #expect(PostcardPriceCopy.badge(priceCents: 399, regularPriceCents: 399, label: "Today only") == nil)
    }
}

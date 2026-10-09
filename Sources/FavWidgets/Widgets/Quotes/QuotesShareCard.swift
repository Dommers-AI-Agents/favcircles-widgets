import FavWidgetsCore

extension QuotesWidget {
    /// Today's quote, leading to that quote in the reel.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let store = QuotesStore.shared(context)
        await store.loadIfNeeded(context: context)
        guard let quote = store.today else { return nil }
        return .quote(text: quote.text, author: quote.author, url: quote.id.flatMap { QuoteShareLink.url(quoteId: $0) })
    }
}

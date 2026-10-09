import FavWidgetsCore

extension StocksWidget {
    /// The market indexes' moves today — never the user's own watchlist.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let quotes = StockQuoteStore.shared(in: context)
        if MarketIndexes.symbols.contains(where: { quotes.quote($0) == nil }) {
            await quotes.refresh(symbols: MarketIndexes.symbols)
        }
        let moves = MarketIndexes.entries.compactMap { entry in
            quotes.quote(entry.symbol)?.changePercent.map { (name: entry.name, percent: $0) }
        }
        return moves.isEmpty ? nil : .markets(moves)
    }
}

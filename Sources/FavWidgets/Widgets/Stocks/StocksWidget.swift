import SwiftUI
import FavWidgetsCore

/// My Stocks: the stocks (ETFs, indexes, crypto) the person follows, in
/// Yahoo Finance's list style — ticker, name, day sparkline, price and a
/// green/red change pill. The list is the synced document; quotes come
/// from Yahoo's public chart endpoint and are cached on the device only.
public struct StocksWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "stocks",
        title: "My Stocks",
        subtitle: "Stocks you follow, live",
        symbolName: "chart.line.uptrend.xyaxis",
        accentHex: "#6001D2",   // Yahoo Finance purple
        category: .money,
        storage: .single,
        // 2 = named lists (`lists`), 1 = flat `entries`. Bump on every shape change:
        // the server refuses a save from a lower schema so an older build can't
        // overwrite lists it can't see.
        schemaVersion: 2
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(StocksCardView(context: context, state: context.state(Watchlist.self), quotes: StockQuoteStore.shared(in: context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(StocksFullView(context: context, state: context.state(Watchlist.self), quotes: StockQuoteStore.shared(in: context)))
    }

    /// The host's per-widget refresh hook: fresh quotes, not just the list
    /// document. (The tab's own pull-to-refresh reloads documents only; quotes
    /// come from the card's first appearance, the poll, and the full view.)
    public func refresh(context: WidgetContext) async {
        let state = context.state(Watchlist.self)
        await state.reload()
        await StockQuoteStore.shared(in: context).refresh(symbols: MarketIndexes.symbols + state.model.symbols, force: true)
    }
}

import SwiftUI
import FavWidgetsCore

/// Card: the top of the watchlist as Yahoo rows (ticker, name, day
/// sparkline, price, change pill) and an "Add" quick action. Renders from
/// the on-device quote cache, so it paints with no network.
struct StocksCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<Watchlist>
    @ObservedObject var quotes: StockQuoteStore

    private static let rowsShown = 4

    var body: some View {
        let theme = context.theme
        let entries = Array(state.model.entries.prefix(Self.rowsShown))

        WidgetCard(context: context, action: quickAction) {
            if entries.isEmpty {
                WidgetUI.summary(state.hasLoaded ? "Add the stocks, ETFs and crypto you follow" : "Loading your list…", theme: theme)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme, compact: true)
                            .padding(.vertical, 5)
                        if entry.id != entries.last?.id {
                            Divider().overlay(theme.separator.opacity(0.5))
                        }
                    }
                    footer(theme: theme)
                }
            }
        }
        .task {
            await state.loadIfNeeded()
            await quotes.refresh(symbols: state.model.symbols)
        }
        .onAppear { quotes.startPolling { state.model.symbols } }
        .onDisappear { quotes.stopPolling() }
    }

    private var quickAction: WidgetQuickAction {
        WidgetQuickAction("Add", symbolName: "plus") {
            quotes.pendingAddRequest = true
            context.track("widget_card_action", ["action": "add_symbol"])
            context.openFullView()
        }
    }

    @ViewBuilder
    private func footer(theme: WidgetTheme) -> some View {
        let hidden = state.model.entries.count - Self.rowsShown
        HStack(spacing: 6) {
            if let status = StockStatusLine.text(state: quotes.marketState(), asOf: quotes.asOf, timezone: quotes.headerTimezone) {
                Text(status)
            }
            if hidden > 0 {
                Text("· \(hidden) more")
            }
            if quotes.isRefreshing {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.secondaryLabel)
        .padding(.top, 6)
    }
}

/// One Yahoo-style watchlist row. `compact` is the card size.
struct StockRow: View {
    let entry: WatchlistEntry
    let quote: StockQuote?
    let theme: WidgetTheme
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.symbol)
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                    .foregroundStyle(theme.label)
                Text(quote?.displayName ?? entry.name)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StockSparklineView(points: quote?.points ?? [], reference: quote?.previousClose,
                               lineWidth: compact ? 1.2 : 1.5, upColor: StockPalette.up, downColor: StockPalette.down)
                .frame(width: compact ? 56 : 72, height: compact ? 22 : 28)

            VStack(alignment: .trailing, spacing: 3) {
                if let quote {
                    Text(StockFormat.price(quote.price, hint: quote.priceHint))
                        .font(.system(size: compact ? 14 : 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.label)
                    if let percent = quote.changePercent {
                        StockChangePill(text: StockFormat.percent(percent), isUp: quote.isUp,
                                        upColor: StockPalette.up, downColor: StockPalette.down)
                    }
                } else {
                    Text("—")
                        .font(.system(size: compact ? 14 : 16, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            .frame(minWidth: compact ? 64 : 80, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let quote else { return "\(entry.symbol), \(entry.name), no quote yet" }
        let change = StockFormat.changeLine(quote) ?? ""
        return "\(entry.symbol), \(quote.displayName), \(StockFormat.price(quote.price, hint: quote.priceHint)) \(change)"
    }
}

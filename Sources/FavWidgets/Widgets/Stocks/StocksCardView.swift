import SwiftUI
import FavWidgetsCore

/// Card: the three US indexes (Nasdaq, Dow, S&P 500), name and day change
/// only — fixed height whatever the person follows — plus a fold-out row
/// (collapsed by default) with the 10-year Treasury yield and Bitcoin. Tap a
/// row for that symbol's detail; the person's own lists live in the full
/// view. Renders from the on-device quote cache, so it paints with no
/// network.
struct StocksCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<Watchlist>
    @ObservedObject var quotes: StockQuoteStore
    /// Rates & crypto fold-out; starts folded every time the card appears
    @State private var extrasExpanded = false

    private var pollSymbols: [String] { MarketIndexes.symbols + MarketExtras.symbols + state.model.symbols }

    var body: some View {
        let theme = context.theme
        let entries = MarketIndexes.entries

        WidgetCard(context: context, action: quickAction) {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button {
                        quotes.pendingDetailSymbol = entry.symbol
                        context.track("widget_card_action", ["action": "open_index", "symbol": entry.symbol])
                        context.openFullView()
                    } label: {
                        StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme, compact: true, percentOnly: true)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if entry.id != entries.last?.id {
                        Divider().overlay(theme.separator.opacity(0.5))
                    }
                }
                Divider().overlay(theme.separator.opacity(0.5))
                extrasSection(theme: theme)
                footer(theme: theme)
            }
        }
        .task {
            await state.loadIfNeeded()
            await quotes.refresh(symbols: pollSymbols)
        }
        .onAppear { quotes.startPolling { MarketIndexes.symbols + MarketExtras.symbols + state.model.symbols } }
        .onDisappear { quotes.stopPolling() }
    }

    /// "10-Yr Treasury · Bitcoin" header with a chevron; the rows fold out
    /// under it (yield as a percent, Bitcoin as a price, each with its day
    /// change) and tap through to detail like the indexes.
    @ViewBuilder
    private func extrasSection(theme: WidgetTheme) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { extrasExpanded.toggle() }
            context.track("widget_card_action", ["action": extrasExpanded ? "expand_extras" : "collapse_extras"])
        } label: {
            HStack(spacing: 6) {
                Text(extrasExpanded ? "Rates & crypto" : extrasSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                    .rotationEffect(.degrees(extrasExpanded ? 180 : 0))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(extrasExpanded ? "Hide rates and crypto" : "Show 10-year Treasury yield and Bitcoin")

        if extrasExpanded {
            ForEach(MarketExtras.entries) { entry in
                Button {
                    quotes.pendingDetailSymbol = entry.symbol
                    context.track("widget_card_action", ["action": "open_extra", "symbol": entry.symbol])
                    context.openFullView()
                } label: {
                    StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme, compact: true,
                             showsSparkline: false,
                             valueText: quotes.quote(entry.symbol).map { MarketExtras.displayValue(symbol: entry.symbol, quote: $0) })
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if entry.id != MarketExtras.entries.last?.id {
                    Divider().overlay(theme.separator.opacity(0.5))
                }
            }
        }
    }

    /// Folded header: the two values inline ("10-Yr 4.12% · BTC $115,230")
    /// so the fold carries information even when closed.
    private var extrasSummary: String {
        let parts: [String] = MarketExtras.entries.map { entry in
            let short = entry.symbol == MarketExtras.treasury10Y ? "10-Yr" : "BTC"
            guard let quote = quotes.quote(entry.symbol) else { return short }
            return "\(short) \(MarketExtras.displayValue(symbol: entry.symbol, quote: quote))"
        }
        return parts.joined(separator: " · ")
    }

    private var quickAction: WidgetQuickAction {
        WidgetQuickAction("My Stocks", symbolName: "list.star") {
            context.track("widget_card_action", ["action": "open_my_stocks"])
            context.openFullView()
        }
    }

    @ViewBuilder
    private func footer(theme: WidgetTheme) -> some View {
        let count = state.model.entries.count
        let lists = state.model.lists.count
        HStack(spacing: 6) {
            if let status = StockStatusLine.text(state: quotes.marketState(), asOf: quotes.asOf, timezone: quotes.headerTimezone) {
                Text(status)
            }
            if state.hasLoaded {
                Text(count == 0 ? "· No stocks yet" : lists > 1 ? "· \(count) stocks in \(lists) lists" : "· \(count) in My Stocks")
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

/// One Yahoo-style watchlist row. `compact` is the card size; `percentOnly`
/// drops the sparkline and price so the row is just name + day change.
struct StockRow: View {
    let entry: WatchlistEntry
    let quote: StockQuote?
    let theme: WidgetTheme
    var compact = false
    var percentOnly = false
    /// Card fold-out rows: value + pill, no chart
    var showsSparkline = true
    /// Overrides the formatted price (the Treasury row shows "4.12%")
    var valueText: String? = nil

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

            if !percentOnly && showsSparkline {
                StockSparklineView(points: quote?.points ?? [], reference: quote?.previousClose,
                                   lineWidth: compact ? 1.2 : 1.5, upColor: StockPalette.up, downColor: StockPalette.down)
                    .frame(width: compact ? 56 : 72, height: compact ? 22 : 28)
            }

            VStack(alignment: .trailing, spacing: 3) {
                if let quote {
                    if !percentOnly {
                        Text(valueText ?? StockFormat.price(quote.price, hint: quote.priceHint))
                            .font(.system(size: compact ? 14 : 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.label)
                    }
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

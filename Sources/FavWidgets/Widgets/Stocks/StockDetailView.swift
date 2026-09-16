import SwiftUI
import FavWidgetsCore

/// One symbol, Yahoo's quote page in miniature: big price and change,
/// status line, range picker with an area chart (dashed previous-close line
/// on the day view), the key stats grid, and Remove.
struct StockDetailView: View {
    let context: WidgetContext
    let entry: WatchlistEntry
    @ObservedObject var quotes: StockQuoteStore
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var range: StockChartRange = .day
    @State private var chart: StockQuote?
    @State private var isLoadingChart = false

    private var quote: StockQuote? { quotes.quote(entry.symbol) }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headline(theme: theme)
                    chartSection(theme: theme)
                    statsSection(theme: theme)
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Text("Remove from My Stocks")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .foregroundStyle(theme.danger)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    Text("Quotes by Yahoo Finance. Prices may be delayed and are for information only.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(entry.symbol)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(context.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { context.host.openURL(yahooPage) } label: {
                        Image(systemName: "safari").font(.system(size: 15))
                    }
                    .foregroundStyle(context.accent)
                    .accessibilityLabel("Open on Yahoo Finance")
                }
            }
        }
        .task(id: range) { await loadChart() }
        .task { await quotes.fetch(entry.symbol) }
    }

    private var yahooPage: URL {
        URL(string: "https://finance.yahoo.com/quote/\(entry.symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.symbol)")!
    }

    // MARK: - Headline

    @ViewBuilder
    private func headline(theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quote?.displayName ?? entry.name)
                .font(.system(size: 15))
                .foregroundStyle(theme.secondaryLabel)
            if let quote {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(StockFormat.price(quote.price, hint: quote.priceHint))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.label)
                    if let line = StockFormat.changeLine(quote) {
                        Text(line)
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(quote.isUp ? StockPalette.up : StockPalette.down)
                    }
                }
                HStack(spacing: 6) {
                    if let status = StockStatusLine.text(state: quote.marketState(), asOf: quote.marketTime, timezone: quote.exchangeTimezone) {
                        Text(status)
                    }
                    if let currency = quote.currency { Text("· \(currency)") }
                    if let exchange = quote.exchangeName { Text("· \(exchange)") }
                }
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
            } else {
                Text("—").font(.system(size: 34, weight: .bold)).foregroundStyle(theme.secondaryLabel)
                Text(quotes.lastError ?? "Fetching quote…").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private func chartSection(theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Range", selection: $range) {
                ForEach(StockChartRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            let series = chart ?? (range == .day ? quote : nil)
            ZStack {
                StockSparklineView(points: series?.points ?? [],
                                   reference: range.showsPreviousCloseLine ? series?.previousClose : nil,
                                   filled: true, lineWidth: 2,
                                   upColor: StockPalette.up, downColor: StockPalette.down)
                if isLoadingChart && series == nil { ProgressView() }
            }
            .frame(height: 180)
            .padding(.vertical, 4)

            if let series, let first = series.points.first, let last = series.points.last, range != .day {
                let change = last.close - first.close
                let percent = first.close != 0 ? change / first.close * 100 : 0
                Text("\(range.rawValue): \(StockFormat.change(change, hint: series.priceHint)) (\(StockFormat.percent(percent)))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(change >= 0 ? StockPalette.up : StockPalette.down)
            } else if range == .day, let previousClose = series?.previousClose {
                Text("Previous close \(StockFormat.price(previousClose, hint: series?.priceHint ?? 2)) shown dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
    }

    private func loadChart() async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        chart = await quotes.chart(entry.symbol, range: range)
    }

    // MARK: - Stats

    @ViewBuilder
    private func statsSection(theme: WidgetTheme) -> some View {
        if let quote {
            let hint = quote.priceHint
            let rows: [(String, String)] = [
                ("Previous close", quote.previousClose.map { StockFormat.price($0, hint: hint) } ?? "—"),
                ("Day's range", rangeText(quote.dayLow, quote.dayHigh, hint: hint)),
                ("52-week range", rangeText(quote.fiftyTwoWeekLow, quote.fiftyTwoWeekHigh, hint: hint)),
                ("Volume", quote.volume.map(StockFormat.compact) ?? "—"),
                ("Exchange", quote.exchangeName ?? "—"),
                ("Type", quote.instrumentType.map(Self.typeLabel) ?? "—")
            ]
            VStack(alignment: .leading, spacing: 10) {
                WidgetUI.header("Key stats", theme: theme)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack {
                            Text(row.0).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                            Spacer()
                            Text(row.1).font(.system(size: 14, weight: .medium)).monospacedDigit().foregroundStyle(theme.label)
                        }
                        .padding(.vertical, 9)
                        if index < rows.count - 1 { Divider().overlay(theme.separator.opacity(0.5)) }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
            }
        }
    }

    private func rangeText(_ low: Double?, _ high: Double?, hint: Int) -> String {
        guard let low, let high else { return "—" }
        return "\(StockFormat.price(low, hint: hint)) – \(StockFormat.price(high, hint: hint))"
    }

    private static func typeLabel(_ type: String) -> String {
        switch type {
        case "EQUITY": return "Stock"
        case "ETF": return "ETF"
        case "INDEX": return "Index"
        case "CRYPTOCURRENCY": return "Crypto"
        case "MUTUALFUND": return "Mutual fund"
        case "CURRENCY": return "Currency"
        default: return type.capitalized
        }
    }
}

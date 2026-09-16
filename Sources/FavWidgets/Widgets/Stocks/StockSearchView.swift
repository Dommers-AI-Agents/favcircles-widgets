import SwiftUI
import FavWidgetsCore

/// Yahoo's symbol search: type a name or ticker, pick a row, it's on the
/// list. Results already on the list show a check instead of a plus.
struct StockSearchView: View {
    let context: WidgetContext
    let existing: Set<String>
    let onPick: (StockSearchHit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [StockSearchHit] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private static let popular: [StockSearchHit] = [
        StockSearchHit(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", typeDisplay: "Equity"),
        StockSearchHit(symbol: "MSFT", name: "Microsoft Corporation", exchange: "NASDAQ", typeDisplay: "Equity"),
        StockSearchHit(symbol: "NVDA", name: "NVIDIA Corporation", exchange: "NASDAQ", typeDisplay: "Equity"),
        StockSearchHit(symbol: "AMZN", name: "Amazon.com, Inc.", exchange: "NASDAQ", typeDisplay: "Equity"),
        StockSearchHit(symbol: "TSLA", name: "Tesla, Inc.", exchange: "NASDAQ", typeDisplay: "Equity"),
        StockSearchHit(symbol: "SPY", name: "SPDR S&P 500 ETF Trust", exchange: "NYSEArca", typeDisplay: "ETF"),
        StockSearchHit(symbol: "^GSPC", name: "S&P 500", exchange: "SNP", typeDisplay: "Index"),
        StockSearchHit(symbol: "BTC-USD", name: "Bitcoin USD", exchange: "CCC", typeDisplay: "Cryptocurrency")
    ]

    var body: some View {
        let theme = context.theme
        NavigationStack {
            VStack(spacing: 0) {
                searchField(theme: theme)
                List {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Section("Popular") {
                            ForEach(Self.popular) { hit in row(hit, theme: theme) }
                        }
                    } else if let errorMessage, hits.isEmpty {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    } else if hits.isEmpty && !isSearching {
                        Text("No matches for “\(query)”").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    } else {
                        ForEach(hits) { hit in row(hit, theme: theme) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Add to My Stocks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(context.accent)
                }
            }
        }
        .onAppear { focused = true }
        .onDisappear { searchTask?.cancel() }
    }

    private func searchField(theme: WidgetTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryLabel)
            TextField("Company, ticker or coin", text: $query)
                .stockSymbolKeyboard()
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.search)
                .onChange(of: query) { _ in scheduleSearch() }
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button { query = ""; hits = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func row(_ hit: StockSearchHit, theme: WidgetTheme) -> some View {
        let onList = existing.contains(Watchlist.normalize(hit.symbol))
        return Button {
            guard !onList else { return }
            onPick(hit)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(theme.label)
                    Text(hit.name).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let type = hit.typeDisplay { Text(type).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel) }
                    if let exchange = hit.exchange { Text(exchange).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel) }
                }
                Image(systemName: onList ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(onList ? StockPalette.up : context.accent)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(onList)
        .listRowBackground(theme.background)
        .accessibilityLabel(onList ? "\(hit.symbol), already on your list" : "Add \(hit.symbol), \(hit.name)")
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            hits = []
            errorMessage = nil
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let results = try await YahooFinanceClient.shared.search(text)
                guard !Task.isCancelled else { return }
                hits = results
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Search failed — check your connection"
            }
        }
    }
}

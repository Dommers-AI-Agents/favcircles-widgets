import SwiftUI
import FavWidgetsCore

/// Full screen: the whole watchlist as Yahoo rows with swipe-to-remove and
/// drag reordering, a status line ("At close: 4:00 PM EDT"), search to add,
/// and a detail sheet per symbol.
struct StocksFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<Watchlist>
    @ObservedObject var quotes: StockQuoteStore

    @State private var showSearch = false
    @State private var selected: WatchlistEntry?

    var body: some View {
        let theme = context.theme
        VStack(spacing: 0) {
            header(theme: theme)
            list(theme: theme)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    #if os(iOS)
                    if !state.model.entries.isEmpty { EditButton() }
                    #endif
                    Button { openSearch() } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Add a symbol")
                }
                .foregroundStyle(context.accent)
            }
        }
        .task {
            await state.loadIfNeeded()
            await quotes.refresh(symbols: MarketIndexes.symbols + state.model.symbols)
            if quotes.pendingAddRequest {
                quotes.pendingAddRequest = false
                showSearch = true
            }
            if let symbol = quotes.pendingDetailSymbol {
                quotes.pendingDetailSymbol = nil
                selected = (MarketIndexes.entries + state.model.entries).first { $0.symbol == symbol }
            }
        }
        .refreshable { await quotes.refresh(symbols: MarketIndexes.symbols + state.model.symbols, force: true) }
        .onAppear { quotes.startPolling { MarketIndexes.symbols + state.model.symbols } }
        .onDisappear { quotes.stopPolling() }
        .sheet(isPresented: $showSearch) {
            StockSearchView(context: context, existing: Set(state.model.symbols)) { hit in
                add(hit)
            }
        }
        .sheet(item: $selected) { entry in
            StockDetailView(context: context, entry: entry, quotes: quotes) {
                remove(entry.symbol)
                selected = nil
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(theme: WidgetTheme) -> some View {
        HStack(spacing: 8) {
            WidgetSyncBadge(state: state.syncState, theme: theme)
            if let status = StockStatusLine.text(state: quotes.marketState(), asOf: quotes.asOf,
                                                 timezone: quotes.headerTimezone) {
                HStack(spacing: 5) {
                    if quotes.marketState() == .live {
                        Circle().fill(StockPalette.up).frame(width: 7, height: 7)
                    }
                    Text(status)
                }
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            if quotes.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let error = quotes.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.warning)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private func list(theme: WidgetTheme) -> some View {
        List {
            Section {
                ForEach(MarketIndexes.entries) { entry in
                    Button { open(entry) } label: {
                        StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.background)
                    .listRowSeparatorTint(theme.separator)
                    .moveDisabled(true)
                    .deleteDisabled(true)
                }
            } header: {
                Text("Indexes").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
            }
            Section {
                if state.hasLoaded && state.model.entries.isEmpty {
                    Text("No stocks yet — add the stocks, ETFs and crypto you follow.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryLabel)
                        .padding(.vertical, 6)
                        .listRowBackground(theme.background)
                        .moveDisabled(true)
                        .deleteDisabled(true)
                }
                ForEach(state.model.entries) { entry in
                    Button { open(entry) } label: {
                        StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.background)
                    .listRowSeparatorTint(theme.separator)
                }
                .onDelete { offsets in
                    let symbols = offsets.map { state.model.entries[$0].symbol }
                    symbols.forEach(remove)
                }
                .onMove { source, destination in
                    state.update { $0.move(fromOffsets: source, toOffset: destination) }
                    context.track("stocks_reordered")
                }

                // Yahoo ends its list with this row; it also means adding never
                // depends on the navigation bar bridging the toolbar button.
                Button(action: openSearch) {
                    Label("Add Symbol", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(context.theme.accent)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.background)
                .moveDisabled(true)
                .deleteDisabled(true)
            } header: {
                Text("My Stocks").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
            } footer: {
                Text("Quotes by Yahoo Finance. Prices may be delayed.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func openSearch() {
        context.track("stocks_search_opened")
        showSearch = true
    }

    private func open(_ entry: WatchlistEntry) {
        context.track("stocks_detail_opened", ["symbol": entry.symbol])
        selected = entry
    }

    private func add(_ hit: StockSearchHit) {
        var added = false
        state.update { added = $0.add(hit.entry) }
        guard added else {
            context.host.presentAlert(WidgetAlert(title: "Already on your list",
                                                  message: state.model.contains(hit.symbol)
                                                      ? "\(hit.symbol) is already in My Stocks."
                                                      : "Your watchlist holds up to \(Watchlist.maxEntries) symbols."))
            return
        }
        context.host.haptic(.success)
        context.track("stocks_symbol_added", ["symbol": hit.symbol])
        Task { await quotes.fetch(hit.symbol) }
    }

    private func remove(_ symbol: String) {
        state.update { $0.remove(symbol) }
        quotes.forget(symbol)
        context.host.haptic(.light)
        context.track("stocks_symbol_removed", ["symbol": symbol])
    }
}

import SwiftUI
import FavWidgetsCore

/// Quotes for the watchlist, shared by the card, the list and the detail
/// sheet. Refreshes are throttled, the last good set is cached on disk so
/// the card paints instantly (and offline) with an "as of" stamp, and a
/// failed refresh keeps what was there rather than blanking the rows.
@MainActor
final class StockQuoteStore: ObservableObject {
    @Published private(set) var quotes: [String: StockQuote] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var lastError: String?
    /// Detail charts by "SYMBOL|range", kept for the session.
    @Published private(set) var charts: [String: StockQuote] = [:]

    /// Set by the card's "Add" action so the full view opens straight into
    /// search.
    var pendingAddRequest = false

    private let client: YahooFinanceClient
    private let cacheURL: URL?
    private var pollTask: Task<Void, Never>?
    private var visiblePollers = 0

    static let minimumRefreshInterval: TimeInterval = 30
    static let pollInterval: TimeInterval = 60

    static func shared(in context: WidgetContext) -> StockQuoteStore {
        context.transient("stocks.quotes") { StockQuoteStore(userId: context.host.currentUserId) }
    }

    init(client: YahooFinanceClient = .shared, userId: String?) {
        self.client = client
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheURL = caches?.appendingPathComponent("favwidgets-stocks-\(userId ?? "anon").json")
        loadCache()
    }

    // MARK: - Reads

    func quote(_ symbol: String) -> StockQuote? { quotes[Watchlist.normalize(symbol)] }

    /// The quotes the header's status line describes: the exchange-traded
    /// ones when there are any (crypto is always "live" and would make a
    /// closed stock market read as open), else whatever is listed.
    private var headerQuotes: [StockQuote] {
        let listed = quotes.values.filter { !$0.isCrypto }
        return listed.isEmpty ? Array(quotes.values) : listed
    }

    /// The freshest "as of" across the list, for the header line.
    var asOf: Date? { headerQuotes.map(\.marketTime).max() }

    /// The zone the header's time is printed in (the exchange's, like Yahoo).
    var headerTimezone: String? {
        headerQuotes.max { $0.marketTime < $1.marketTime }?.exchangeTimezone
    }

    /// One market state for the header: live if any exchange is trading.
    func marketState(now: Date = Date()) -> StockMarketState? {
        let states = headerQuotes.map { $0.marketState(now: now) }
        if states.isEmpty { return nil }
        if states.contains(.live) { return .live }
        if states.contains(.preMarket) { return .preMarket }
        if states.contains(.afterHours) { return .afterHours }
        return .closed
    }

    /// Polling only matters while something can move: an open exchange, or
    /// crypto on the list.
    var somethingIsTrading: Bool {
        quotes.values.contains { $0.isCrypto } || marketState() == .live
    }

    // MARK: - Refresh

    /// Fetches every symbol; throttled unless `force`. Symbols that fail keep
    /// their previous quote.
    func refresh(symbols: [String], force: Bool = false) async {
        let wanted = symbols.map(Watchlist.normalize)
        guard !wanted.isEmpty else { return }
        if !force, let last = lastRefreshed, Date().timeIntervalSince(last) < Self.minimumRefreshInterval,
           wanted.allSatisfy({ quotes[$0] != nil }) {
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let results = await client.quotes(symbols: wanted)
        var failures: [String] = []
        for (symbol, result) in results {
            switch result {
            case .success(let quote): quotes[symbol] = quote
            case .failure(let error):
                failures.append(symbol)
                if quotes[symbol] == nil, let known = error as? StockQuoteError, case .notFound = known {
                    // Nothing to show and never will be; the row says so
                    lastError = known.errorDescription
                }
            }
        }
        if failures.count == results.count, let first = failures.first, let error = results[first],
           case .failure(let underlying) = error {
            lastError = (underlying as? LocalizedError)?.errorDescription ?? "Couldn't reach Yahoo Finance"
        } else if failures.isEmpty {
            lastError = nil
        }
        lastRefreshed = Date()
        saveCache()
    }

    /// Fetches a symbol on its own (a fresh addition), outside the throttle.
    func fetch(_ symbol: String) async {
        let key = Watchlist.normalize(symbol)
        if let quote = try? await client.quote(symbol: key) {
            quotes[key] = quote
            saveCache()
        }
    }

    func chart(_ symbol: String, range: StockChartRange) async -> StockQuote? {
        let key = "\(Watchlist.normalize(symbol))|\(range.rawValue)"
        if let cached = charts[key], Date().timeIntervalSince(cached.fetchedAt) < Self.pollInterval { return cached }
        guard let quote = try? await client.quote(symbol: symbol, range: range) else { return charts[key] }
        charts[key] = quote
        return quote
    }

    func forget(_ symbol: String) {
        quotes[Watchlist.normalize(symbol)] = nil
        saveCache()
    }

    // MARK: - Polling while a view is on screen

    /// Refreshes every minute while at least one view is visible. Views call
    /// this in `onAppear` and `stopPolling` in `onDisappear`.
    func startPolling(symbols: @escaping () -> [String]) {
        visiblePollers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                guard !Task.isCancelled, let self else { return }
                let list = symbols()
                // Outside market hours nothing moves; one poll per open is enough
                if self.somethingIsTrading || self.quotes.isEmpty {
                    await self.refresh(symbols: list, force: true)
                }
            }
        }
    }

    func stopPolling() {
        visiblePollers = max(0, visiblePollers - 1)
        if visiblePollers == 0 {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Disk cache

    private struct CacheFile: Codable {
        var quotes: [String: StockQuote]
        var lastRefreshed: Date?
    }

    private func loadCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else { return }
        quotes = file.quotes
        lastRefreshed = file.lastRefreshed
    }

    private func saveCache() {
        guard let cacheURL, let data = try? JSONEncoder().encode(CacheFile(quotes: quotes, lastRefreshed: lastRefreshed)) else { return }
        try? data.write(to: cacheURL, options: [.atomic])
    }
}

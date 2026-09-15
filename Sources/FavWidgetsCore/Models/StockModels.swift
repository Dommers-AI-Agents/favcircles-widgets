import Foundation

// MARK: - The synced document

/// One symbol the person follows. `symbol` is the Yahoo ticker ("AAPL",
/// "BTC-USD", "^GSPC"); name and exchange are copied from the search hit so
/// the list renders before any quote arrives.
public struct WatchlistEntry: Codable, Equatable, Identifiable, Sendable {
    public var symbol: String
    public var name: String
    public var exchange: String?
    public var addedAt: Date

    public var id: String { symbol }

    public init(symbol: String, name: String, exchange: String? = nil, addedAt: Date = Date()) {
        self.symbol = Watchlist.normalize(symbol)
        self.name = name
        self.exchange = exchange
        self.addedAt = addedAt
    }
}

/// Single document (`stocks`): the ordered watchlist. Quotes are never
/// stored here — they change every minute and would churn the version
/// counter (and conflict across devices) for data that is worthless once
/// stale. The widget caches quotes on the device instead.
public struct Watchlist: WidgetModel {
    public var entries: [WatchlistEntry]

    /// Yahoo caps a free list at a similar size; past this the row fan-out
    /// per refresh (one request per symbol) stops being cheap.
    public static let maxEntries = 50

    public init(entries: [WatchlistEntry] = []) {
        self.entries = entries
    }

    public static let empty = Watchlist()

    public var symbols: [String] { entries.map(\.symbol) }

    public func contains(_ symbol: String) -> Bool {
        let key = Self.normalize(symbol)
        return entries.contains { $0.symbol == key }
    }

    /// Tickers are case-insensitive on Yahoo; store them the way Yahoo
    /// prints them.
    public static func normalize(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Appends unless already present or the list is full. Returns whether
    /// the entry was added.
    @discardableResult
    public mutating func add(_ entry: WatchlistEntry) -> Bool {
        guard !contains(entry.symbol), entries.count < Self.maxEntries else { return false }
        entries.append(entry)
        return true
    }

    public mutating func remove(_ symbol: String) {
        let key = Self.normalize(symbol)
        entries.removeAll { $0.symbol == key }
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)` (which
    /// isn't available in this Foundation-only module): `destination` is an
    /// index into the list *before* removal.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        guard !moving.isEmpty else { return }
        let removedBefore = source.filter { $0 < destination }.count
        entries.removeAll { entry in moving.contains { $0.symbol == entry.symbol } }
        let target = max(0, min(entries.count, destination - removedBefore))
        entries.insert(contentsOf: moving, at: target)
    }

    /// Two devices edited the list: keep the local order and append anything
    /// the other device has that this one doesn't. That's a union — a symbol
    /// removed on one device while the other added elsewhere comes back,
    /// which is the safe side of a rare conflict (a stray row beats a lost
    /// one, and it's one swipe to remove again).
    public static func merge(local: Watchlist, remote: Watchlist) -> Watchlist {
        var merged = local
        for entry in remote.entries where !merged.contains(entry.symbol) {
            merged.entries.append(entry)
        }
        if merged.entries.count > maxEntries {
            merged.entries.removeLast(merged.entries.count - maxEntries)
        }
        return merged
    }
}

// MARK: - Quotes (device-cached, never synced)

/// One point on a price chart.
public struct StockPricePoint: Codable, Equatable, Sendable {
    public let time: Date
    public let close: Double

    public init(time: Date, close: Double) {
        self.time = time
        self.close = close
    }
}

public enum StockMarketState: Equatable, Sendable {
    /// The regular session is open and the price is moving.
    case live
    /// Outside the regular session; the number is the last close.
    case closed
    /// Before today's open (the price shown is still yesterday's close).
    case preMarket
    /// After today's close.
    case afterHours
}

/// A quote as Yahoo's chart endpoint reports it, plus the day's closes for
/// the sparkline. Change is relative to the previous close, which is what
/// Yahoo colors on, so a stock that gapped up and drifted all day is still
/// green as long as it sits above yesterday's close.
public struct StockQuote: Codable, Equatable, Sendable {
    public let symbol: String
    public let shortName: String?
    public let longName: String?
    public let currency: String?
    public let exchangeName: String?
    public let instrumentType: String?
    public let price: Double
    public let previousClose: Double?
    public let dayHigh: Double?
    public let dayLow: Double?
    public let fiftyTwoWeekHigh: Double?
    public let fiftyTwoWeekLow: Double?
    public let volume: Int?
    /// Decimal places Yahoo renders the price with (2 for most equities,
    /// more for pennies and crypto).
    public let priceHint: Int
    /// When `price` was last updated.
    public let marketTime: Date
    /// Today's regular session, when Yahoo knows it.
    public let regularSessionStart: Date?
    public let regularSessionEnd: Date?
    public let exchangeTimezone: String?
    public let points: [StockPricePoint]
    /// When this quote was fetched (for the "as of" line).
    public var fetchedAt: Date

    public init(symbol: String, shortName: String?, longName: String?, currency: String?, exchangeName: String?,
                instrumentType: String?, price: Double, previousClose: Double?, dayHigh: Double?, dayLow: Double?,
                fiftyTwoWeekHigh: Double?, fiftyTwoWeekLow: Double?, volume: Int?, priceHint: Int, marketTime: Date,
                regularSessionStart: Date?, regularSessionEnd: Date?, exchangeTimezone: String?,
                points: [StockPricePoint], fetchedAt: Date = Date()) {
        self.symbol = symbol
        self.shortName = shortName
        self.longName = longName
        self.currency = currency
        self.exchangeName = exchangeName
        self.instrumentType = instrumentType
        self.price = price
        self.previousClose = previousClose
        self.dayHigh = dayHigh
        self.dayLow = dayLow
        self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
        self.fiftyTwoWeekLow = fiftyTwoWeekLow
        self.volume = volume
        self.priceHint = priceHint
        self.marketTime = marketTime
        self.regularSessionStart = regularSessionStart
        self.regularSessionEnd = regularSessionEnd
        self.exchangeTimezone = exchangeTimezone
        self.points = points
        self.fetchedAt = fetchedAt
    }

    /// The name Yahoo shows under the ticker.
    public var displayName: String { shortName ?? longName ?? symbol }

    public var change: Double? {
        guard let previousClose else { return nil }
        return price - previousClose
    }

    public var changePercent: Double? {
        guard let previousClose, previousClose != 0 else { return nil }
        return (price - previousClose) / previousClose * 100
    }

    public var isUp: Bool { (change ?? 0) >= 0 }

    public var isCrypto: Bool { instrumentType == "CRYPTOCURRENCY" }

    /// Where the market is relative to `now`. Crypto trades around the clock.
    public func marketState(now: Date = Date()) -> StockMarketState {
        if isCrypto { return .live }
        guard let start = regularSessionStart, let end = regularSessionEnd else { return .closed }
        if now < start { return .preMarket }
        if now >= end { return .afterHours }
        return .live
    }
}

/// A row from Yahoo's symbol search.
public struct StockSearchHit: Equatable, Identifiable, Sendable {
    public let symbol: String
    public let name: String
    public let exchange: String?
    /// "Equity", "ETF", "Cryptocurrency", "Index"…
    public let typeDisplay: String?

    public var id: String { symbol }

    public init(symbol: String, name: String, exchange: String?, typeDisplay: String?) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.typeDisplay = typeDisplay
    }

    public var entry: WatchlistEntry {
        WatchlistEntry(symbol: symbol, name: name, exchange: exchange)
    }
}

/// The ranges Yahoo's detail chart offers, with the bar size each uses.
public enum StockChartRange: String, CaseIterable, Sendable {
    case day = "1D", week = "1W", month = "1M", sixMonths = "6M", yearToDate = "YTD", year = "1Y", fiveYears = "5Y"

    public var yahooRange: String {
        switch self {
        case .day: return "1d"
        case .week: return "5d"
        case .month: return "1mo"
        case .sixMonths: return "6mo"
        case .yearToDate: return "ytd"
        case .year: return "1y"
        case .fiveYears: return "5y"
        }
    }

    public var yahooInterval: String {
        switch self {
        case .day: return "5m"
        case .week: return "15m"
        case .month: return "1h"
        case .sixMonths, .yearToDate, .year: return "1d"
        case .fiveYears: return "1wk"
        }
    }

    /// Only the intraday chart compares against yesterday's close.
    public var showsPreviousCloseLine: Bool { self == .day }
}

import Foundation

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

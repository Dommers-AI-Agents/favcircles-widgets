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

/// The three headline US indexes the card always shows. They are not part
/// of the watchlist document — nobody has to add them and they can't be
/// removed — but they ride the same quote store as everything else.
public enum MarketIndexes {
    public static let entries: [WatchlistEntry] = [
        WatchlistEntry(symbol: "^IXIC", name: "Nasdaq", exchange: "NASDAQ", addedAt: Date(timeIntervalSince1970: 0)),
        WatchlistEntry(symbol: "^DJI", name: "Dow Jones", exchange: "DJI", addedAt: Date(timeIntervalSince1970: 0)),
        WatchlistEntry(symbol: "^GSPC", name: "S&P 500", exchange: "SNP", addedAt: Date(timeIntervalSince1970: 0))
    ]
    public static var symbols: [String] { entries.map(\.symbol) }
}

/// The card's fold-out row under the indexes: the 10-year Treasury yield
/// and Bitcoin. Same quote pipeline; ^TNX's "price" IS the yield in percent.
public enum MarketExtras {
    public static let treasury10Y = "^TNX"
    public static let bitcoin = "BTC-USD"
    public static let entries: [WatchlistEntry] = [
        WatchlistEntry(symbol: treasury10Y, name: "10-Yr Treasury yield", exchange: "CBOE", addedAt: Date(timeIntervalSince1970: 0)),
        WatchlistEntry(symbol: bitcoin, name: "Bitcoin", exchange: "CCC", addedAt: Date(timeIntervalSince1970: 0))
    ]
    public static var symbols: [String] { entries.map(\.symbol) }

    /// "4.12%" for the yield, a normal price for everything else.
    public static func displayValue(symbol: String, quote: StockQuote) -> String {
        if symbol == treasury10Y { return StockFormat.price(quote.price, hint: 2) + "%" }
        return StockFormat.price(quote.price, hint: quote.priceHint)
    }
}

/// One named list inside My Stocks ("Tech", "Crypto", …).
public struct StockList: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var entries: [WatchlistEntry]
    /// Folded up in the full view (rows hidden, count shown). Synced with
    /// the list so every device agrees.
    public var isCollapsed: Bool

    public init(id: UUID = UUID(), name: String, entries: [WatchlistEntry] = [], isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.entries = entries
        self.isCollapsed = isCollapsed
    }

    private enum CodingKeys: String, CodingKey { case id, name, entries, isCollapsed }

    /// Lists written before `isCollapsed` existed decode as expanded.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        entries = try c.decodeIfPresent([WatchlistEntry].self, forKey: .entries) ?? []
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }

    public var symbols: [String] { entries.map(\.symbol) }

    public func contains(_ symbol: String) -> Bool {
        let key = Watchlist.normalize(symbol)
        return entries.contains { $0.symbol == key }
    }
}

/// Single document (`stocks`): the person's named lists, each an ordered
/// set of symbols. Quotes are never stored here — they change every minute
/// and would churn the version counter (and conflict across devices) for
/// data that is worthless once stale. The widget caches quotes on the
/// device instead.
///
/// Documents written before lists existed carried a flat `entries` array;
/// those decode into one list named "My Stocks".
public struct Watchlist: WidgetModel {
    public static let defaultListName = "My Stocks"
    public var lists: [StockList]

    /// Yahoo caps a free list at a similar size; past this the row fan-out
    /// per refresh (one request per symbol) stops being cheap.
    public static let maxEntries = 50
    public static let maxLists = 10

    public init(lists: [StockList]) {
        self.lists = lists
    }

    /// One list holding `entries` (the pre-lists shape, still used by tests
    /// and callers that don't care about lists).
    public init(entries: [WatchlistEntry] = []) {
        self.lists = entries.isEmpty ? [] : [StockList(name: Self.defaultListName, entries: entries)]
    }

    public static let empty = Watchlist()

    private enum CodingKeys: String, CodingKey { case lists, entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let lists = try c.decodeIfPresent([StockList].self, forKey: .lists) {
            self.lists = lists
        } else {
            let entries = try c.decodeIfPresent([WatchlistEntry].self, forKey: .entries) ?? []
            self.lists = entries.isEmpty ? [] : [StockList(name: Self.defaultListName, entries: entries)]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lists, forKey: .lists)
        // The flat union as well: a reader that only knows `entries` still
        // sees every symbol (the server blocks it from saving over `lists`).
        try c.encode(entries, forKey: .entries)
    }

    // MARK: Across every list

    /// Every entry, first occurrence wins when a symbol is in two lists.
    public var entries: [WatchlistEntry] {
        var seen = Set<String>()
        return lists.flatMap(\.entries).filter { seen.insert($0.symbol).inserted }
    }

    public var symbols: [String] { entries.map(\.symbol) }

    public func contains(_ symbol: String) -> Bool {
        lists.contains { $0.contains(symbol) }
    }

    public func list(id: UUID) -> StockList? { lists.first { $0.id == id } }

    /// Tickers are case-insensitive on Yahoo; store them the way Yahoo
    /// prints them.
    public static func normalize(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: Lists

    /// Adds a list; returns its id, or nil when the name is blank or the
    /// cap is reached.
    @discardableResult
    public mutating func addList(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, lists.count < Self.maxLists else { return nil }
        let list = StockList(name: trimmed)
        lists.append(list)
        return list.id
    }

    public mutating func renameList(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].name = trimmed
    }

    public mutating func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
    }

    public mutating func moveLists(fromOffsets source: IndexSet, toOffset destination: Int) {
        lists = Self.moved(lists, fromOffsets: source, toOffset: destination) { $0.id == $1.id }
    }

    /// Swap a list with its neighbour (the header menu's Move up / Move down).
    public mutating func moveList(_ id: UUID, by delta: Int) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard lists.indices.contains(target) else { return }
        lists.swapAt(index, target)
    }

    public mutating func setCollapsed(_ collapsed: Bool, listId: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[index].isCollapsed = collapsed
    }

    // MARK: Entries

    /// The list new symbols go to when no list is named: the first one,
    /// created as "My Stocks" if there is none.
    private mutating func defaultListIndex() -> Int {
        if lists.isEmpty { lists.append(StockList(name: Self.defaultListName)) }
        return 0
    }

    /// Appends unless already in that list or the list is full. Returns
    /// whether the entry was added.
    @discardableResult
    public mutating func add(_ entry: WatchlistEntry, to listId: UUID? = nil) -> Bool {
        let index: Int
        if let listId {
            guard let i = lists.firstIndex(where: { $0.id == listId }) else { return false }
            index = i
        } else {
            index = defaultListIndex()
        }
        guard !lists[index].contains(entry.symbol), lists[index].entries.count < Self.maxEntries else { return false }
        lists[index].entries.append(entry)
        return true
    }

    /// Removes the symbol from one list, or from every list when `listId`
    /// is nil.
    public mutating func remove(_ symbol: String, from listId: UUID? = nil) {
        let key = Self.normalize(symbol)
        for i in lists.indices where listId == nil || lists[i].id == listId {
            lists[i].entries.removeAll { $0.symbol == key }
        }
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)` (which
    /// isn't available in this Foundation-only module): `destination` is an
    /// index into the list *before* removal. Reorders within one list (the
    /// first when `listId` is nil).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, in listId: UUID? = nil) {
        guard let index = listId.map({ id in lists.firstIndex { $0.id == id } }) ?? (lists.isEmpty ? nil : 0) else { return }
        lists[index].entries = Self.moved(lists[index].entries, fromOffsets: source, toOffset: destination) { $0.symbol == $1.symbol }
    }

    private static func moved<T>(_ items: [T], fromOffsets source: IndexSet, toOffset destination: Int, same: (T, T) -> Bool) -> [T] {
        let moving = source.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil }
        guard !moving.isEmpty else { return items }
        let removedBefore = source.filter { $0 < destination }.count
        var rest = items.filter { item in !moving.contains { same($0, item) } }
        let target = max(0, min(rest.count, destination - removedBefore))
        rest.insert(contentsOf: moving, at: target)
        return rest
    }

    /// Two devices edited the lists: keep the local order and append
    /// anything the other device has that this one doesn't, list by list
    /// (matched by id; lists only the remote has are appended). That's a
    /// union — a symbol removed on one device while the other added
    /// elsewhere comes back, which is the safe side of a rare conflict (a
    /// stray row beats a lost one, and it's one swipe to remove again).
    public static func merge(local: Watchlist, remote: Watchlist) -> Watchlist {
        var merged = local
        for remoteList in remote.lists {
            if let i = merged.lists.firstIndex(where: { $0.id == remoteList.id }) {
                for entry in remoteList.entries where !merged.lists[i].contains(entry.symbol) {
                    merged.lists[i].entries.append(entry)
                }
                if merged.lists[i].entries.count > maxEntries {
                    merged.lists[i].entries.removeLast(merged.lists[i].entries.count - maxEntries)
                }
            } else if merged.lists.count < maxLists {
                merged.lists.append(remoteList)
            }
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

import Foundation

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

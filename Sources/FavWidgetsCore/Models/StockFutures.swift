import Foundation

/// Futures in the Stocks widget (Wes, 2026-11-17: "MNQ nasdaq mini future and
/// others"). Only Yahoo's continuous front-month symbols ("MNQ=F", "ES=F",
/// "GC=F"): they roll to the next contract by themselves, so a watchlist row
/// never expires. Dated contracts ("MNQZ26.CME") stay out of search.
public enum StockFutures {
    /// "MNQ=F" yes; "MNQZ26.CME" and "AAPL" no
    public static func isContinuous(_ symbol: String) -> Bool {
        let s = Watchlist.normalize(symbol)
        return s.hasSuffix("=F") && s.count > 2
    }

    /// "MNQ" for "MNQ=F"
    public static func root(_ symbol: String) -> String {
        String(Watchlist.normalize(symbol).dropLast(2))
    }

    /// The popular contracts, named the way traders say them. Yahoo's own
    /// names are cut at 30 characters and carry the current month ("Nasdaq
    /// 100 Dec 26"), which is wrong a month later.
    static let names: [String: String] = [
        "MNQ": "Micro Nasdaq-100 futures", "NQ": "Nasdaq-100 futures",
        "MES": "Micro S&P 500 futures", "ES": "S&P 500 futures",
        "MYM": "Micro Dow futures", "YM": "Dow futures",
        "M2K": "Micro Russell 2000 futures", "RTY": "Russell 2000 futures",
        "MCL": "Micro crude oil futures", "CL": "Crude oil futures",
        "MGC": "Micro gold futures", "GC": "Gold futures",
        "SIL": "Micro silver futures", "SI": "Silver futures",
        "NG": "Natural gas futures", "HG": "Copper futures",
        "ZN": "10-Year Treasury note futures", "ZB": "30-Year Treasury bond futures",
        "ZF": "5-Year Treasury note futures", "ZT": "2-Year Treasury note futures",
        "MBT": "Micro Bitcoin futures", "BTC": "Bitcoin futures",
        "MET": "Micro Ether futures", "ETH": "Ether futures",
        "ZC": "Corn futures", "ZS": "Soybean futures", "ZW": "Wheat futures",
        "6E": "Euro FX futures", "6J": "Japanese yen futures", "VX": "VIX futures"
    ]

    /// A stable name for a continuous contract: the table's, else Yahoo's
    /// with the contract month and the cut-off "F" taken off.
    public static func name(symbol: String, yahooName: String?) -> String {
        if let known = names[root(symbol)] { return known }
        var name = (yahooName ?? "").trimmingCharacters(in: .whitespaces)
        let month = #"[,\s]+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[-\s]+\d{0,4}\s*$"#
        name = name.replacingOccurrences(of: month, with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"[,\s]+(F|Fu|Fut|Futu|Futur|Future|Futures)?[,\s]*$"#, with: "", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        if name.isEmpty { return "\(root(symbol)) futures" }
        return name.range(of: "futur", options: .caseInsensitive) == nil ? "\(name) futures" : name
    }

    /// Search order: a future goes where Yahoo ranked it when the search is
    /// plainly for it ("MNQ", "nasdaq futures"), else after the stocks and
    /// funds, so "Apple" leads with Apple and not Apple single-stock futures.
    public static func rank(_ hits: [StockSearchHit], query: String?) -> [StockSearchHit] {
        guard let raw = query?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return hits }
        let q = raw.uppercased()
        let wantsFutures = q.contains("FUTUR") || q.hasSuffix("=F")
        let isWanted: (StockSearchHit) -> Bool = { hit in
            !isContinuous(hit.symbol) || wantsFutures || root(hit.symbol) == q
        }
        return hits.filter(isWanted) + hits.filter { !isWanted($0) }
    }
}

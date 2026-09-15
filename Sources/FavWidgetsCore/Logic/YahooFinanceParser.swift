import Foundation

public enum StockQuoteError: Error, LocalizedError, Equatable, Sendable {
    /// Yahoo has no such symbol (or it was delisted).
    case notFound(symbol: String, reason: String)
    /// The response wasn't the shape we know; the feed is unofficial and
    /// can change without notice.
    case malformed(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let symbol, _): return "\(symbol) isn't a symbol Yahoo Finance knows"
        case .malformed: return "Yahoo Finance sent something unexpected"
        case .network(let message): return message
        }
    }
}

/// Turns Yahoo Finance's chart and search JSON into our types. Pure, so the
/// unofficial feed's shape is pinned by tests against real captured
/// responses and a change on their side fails loudly here.
public enum YahooFinanceParser {
    // MARK: - Chart → quote

    public static func quote(from data: Data, symbol requested: String, fetchedAt: Date = Date()) throws -> StockQuote {
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw StockQuoteError.malformed("not an object")
            }
            root = object
        } catch let error as StockQuoteError {
            throw error
        } catch {
            throw StockQuoteError.malformed("not JSON")
        }

        guard let chart = root["chart"] as? [String: Any] else { throw StockQuoteError.malformed("no chart") }
        if let error = chart["error"] as? [String: Any] {
            let description = (error["description"] as? String) ?? (error["code"] as? String) ?? "unknown"
            throw StockQuoteError.notFound(symbol: requested, reason: description)
        }
        guard let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let price = number(meta["regularMarketPrice"]) else {
            throw StockQuoteError.malformed("no result")
        }

        let timestamps = (result["timestamp"] as? [Any])?.compactMap(number) ?? []
        let closes = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"] as? [Any] ?? []
        var points: [StockPricePoint] = []
        points.reserveCapacity(timestamps.count)
        for (index, stamp) in timestamps.enumerated() where index < closes.count {
            // Yahoo pads missing bars with null; skip them rather than draw zeros
            guard let close = number(closes[index]) else { continue }
            points.append(StockPricePoint(time: Date(timeIntervalSince1970: stamp), close: close))
        }

        let regular = (meta["currentTradingPeriod"] as? [String: Any])?["regular"] as? [String: Any]
        return StockQuote(
            symbol: (meta["symbol"] as? String) ?? Watchlist.normalize(requested),
            shortName: meta["shortName"] as? String,
            longName: meta["longName"] as? String,
            currency: meta["currency"] as? String,
            exchangeName: meta["fullExchangeName"] as? String ?? meta["exchangeName"] as? String,
            instrumentType: meta["instrumentType"] as? String,
            price: price,
            previousClose: number(meta["previousClose"]) ?? number(meta["chartPreviousClose"]),
            dayHigh: number(meta["regularMarketDayHigh"]),
            dayLow: number(meta["regularMarketDayLow"]),
            fiftyTwoWeekHigh: number(meta["fiftyTwoWeekHigh"]),
            fiftyTwoWeekLow: number(meta["fiftyTwoWeekLow"]),
            volume: number(meta["regularMarketVolume"]).map { Int($0) },
            priceHint: number(meta["priceHint"]).map { Int($0) } ?? 2,
            marketTime: number(meta["regularMarketTime"]).map { Date(timeIntervalSince1970: $0) } ?? fetchedAt,
            regularSessionStart: number(regular?["start"]).map { Date(timeIntervalSince1970: $0) },
            regularSessionEnd: number(regular?["end"]).map { Date(timeIntervalSince1970: $0) },
            exchangeTimezone: meta["exchangeTimezoneName"] as? String,
            points: points,
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Search → hits

    /// Instruments a watchlist can hold. Futures and options are dropped:
    /// their tickers expire and the chart endpoint rarely has them.
    static let searchableTypes: Set<String> = ["EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY", "MUTUALFUND", "CURRENCY"]

    public static func searchHits(from data: Data) throws -> [StockSearchHit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = root["quotes"] as? [[String: Any]] else {
            throw StockQuoteError.malformed("no quotes")
        }
        return quotes.compactMap { quote in
            guard let symbol = quote["symbol"] as? String, !symbol.isEmpty,
                  let type = quote["quoteType"] as? String, searchableTypes.contains(type),
                  (quote["isYahooFinance"] as? Bool) != false else { return nil }
            let name = (quote["shortname"] as? String) ?? (quote["longname"] as? String) ?? symbol
            return StockSearchHit(symbol: symbol, name: name,
                                  exchange: quote["exchDisp"] as? String,
                                  typeDisplay: quote["typeDisp"] as? String)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }
}

/// The strings Yahoo's rows show: "331.34", "-1.74 (-0.52%)", "31.42M".
public enum StockFormat {
    public static func price(_ value: Double, hint: Int = 2) -> String {
        let decimals = min(max(hint, 2), 6)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }

    /// "+1.23" / "-1.23"; the sign is always shown, like Yahoo's pill.
    public static func change(_ value: Double, hint: Int = 2) -> String {
        (value >= 0 ? "+" : "-") + price(abs(value), hint: hint)
    }

    public static func percent(_ value: Double) -> String {
        (value >= 0 ? "+" : "-") + String(format: "%.2f%%", abs(value))
    }

    /// "+1.23 (+0.45%)" — nil when there is no previous close to compare to.
    public static func changeLine(_ quote: StockQuote) -> String? {
        guard let change = quote.change, let percent = quote.changePercent else { return nil }
        return "\(self.change(change, hint: quote.priceHint)) (\(self.percent(percent)))"
    }

    /// 31,420,574 → "31.42M"; 1,234 → "1,234".
    public static func compact(_ value: Int) -> String {
        let magnitude = Double(value)
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (threshold, suffix) in units where magnitude >= threshold {
            let scaled = magnitude / threshold
            return String(format: scaled >= 100 ? "%.0f%@" : "%.2f%@", scaled, suffix)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to Yahoo Finance's public (unofficial, unauthenticated) chart and
/// search endpoints. There is no SLA: Yahoo has changed and rate-limited
/// these before, which is why every caller keeps the last good quotes and
/// treats a failed refresh as "show what we have, dated".
///
/// The transport is injectable so the parser and the batching are tested
/// without the network.
public final class YahooFinanceClient: @unchecked Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public static let shared = YahooFinanceClient()

    private let fetch: Fetch
    /// Parallel requests per refresh. A watchlist is one request per symbol;
    /// this keeps a 50-row list from opening 50 sockets at once.
    private let concurrency: Int

    public init(fetch: Fetch? = nil, concurrency: Int = 6) {
        self.fetch = fetch ?? Self.urlSessionFetch
        self.concurrency = max(1, concurrency)
    }

    // MARK: - URLs

    public static func chartURL(symbol: String, range: StockChartRange) -> URL {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encode(symbol))")!
        components.queryItems = [
            URLQueryItem(name: "range", value: range.yahooRange),
            URLQueryItem(name: "interval", value: range.yahooInterval),
            URLQueryItem(name: "includePrePost", value: "false")
        ]
        return components.url!
    }

    public static func searchURL(query: String, limit: Int = 8) -> URL {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "\(limit)"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "listsCount", value: "0")
        ]
        return components.url!
    }

    /// Tickers like "^GSPC" and "BRK-B" must survive the path.
    private static func encode(_ symbol: String) -> String {
        Watchlist.normalize(symbol).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
    }

    // MARK: - Calls

    public func quote(symbol: String, range: StockChartRange = .day) async throws -> StockQuote {
        let data = try await fetch(Self.chartURL(symbol: symbol, range: range))
        return try YahooFinanceParser.quote(from: data, symbol: symbol)
    }

    /// One request per symbol, a few at a time. Symbols that fail come back
    /// as their error so the list can keep the other rows fresh.
    public func quotes(symbols: [String]) async -> [String: Result<StockQuote, Error>] {
        let unique = Array(NSOrderedSet(array: symbols.map(Watchlist.normalize))) as? [String] ?? []
        var results: [String: Result<StockQuote, Error>] = [:]
        var index = 0
        while index < unique.count {
            let batch = Array(unique[index..<min(index + concurrency, unique.count)])
            index += batch.count
            await withTaskGroup(of: (String, Result<StockQuote, Error>).self) { group in
                for symbol in batch {
                    group.addTask { [self] in
                        do {
                            return (symbol, .success(try await self.quote(symbol: symbol)))
                        } catch {
                            return (symbol, .failure(error))
                        }
                    }
                }
                for await (symbol, result) in group {
                    results[symbol] = result
                }
            }
        }
        return results
    }

    public func search(_ query: String) async throws -> [StockSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let data = try await fetch(Self.searchURL(query: trimmed))
        return try YahooFinanceParser.searchHits(from: data)
    }

    // MARK: - Transport

    /// Yahoo answers a bare URLSession agent with 429s; a browser agent is
    /// what every other unofficial client sends.
    private static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode), http.statusCode != 404 {
            // 404 carries Yahoo's own error envelope, which the parser reports
            // as "not found"; anything else is the transport's problem.
            throw StockQuoteError.network(http.statusCode == 429 ? "Yahoo Finance is rate limiting — try again in a minute"
                                                                 : "Yahoo Finance returned \(http.statusCode)")
        }
        return data
    }
}

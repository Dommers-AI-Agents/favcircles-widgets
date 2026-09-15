import Testing
import Foundation
@testable import FavWidgetsCore

struct YahooFinanceParserTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func parsesAnEquityChartIntoAQuote() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_789_502_500)
        let q = try YahooFinanceParser.quote(from: data(StockFixtures.aaplDay), symbol: "aapl", fetchedAt: fetchedAt)
        #expect(q.symbol == "AAPL")
        #expect(q.displayName == "Apple Inc.")
        #expect(q.exchangeName == "NasdaqGS")
        #expect(q.currency == "USD")
        #expect(q.price == 331.34)
        #expect(q.previousClose == 333.08)
        #expect(abs((q.change ?? 0) - (-1.74)) < 0.0001)
        #expect(abs((q.changePercent ?? 0) - (-0.5224)) < 0.001)
        #expect(!q.isUp)
        #expect(q.dayHigh == 331.76 && q.dayLow == 328.35)
        #expect(q.fiftyTwoWeekHigh == 344.57 && q.fiftyTwoWeekLow == 236.32)
        #expect(q.volume == 31_420_574)
        #expect(q.priceHint == 2)
        #expect(q.marketTime == Date(timeIntervalSince1970: 1_789_502_401))
        #expect(q.points.count == 8)
        #expect(abs(q.points[0].close - 329.54) < 0.01)
        #expect(abs((q.points.last?.close ?? 0) - 331.34) < 0.01)
        #expect(q.fetchedAt == fetchedAt)
        #expect(!q.isCrypto)
    }

    @Test func marketStateComesFromTheRegularSession() throws {
        let q = try YahooFinanceParser.quote(from: data(StockFixtures.aaplDay), symbol: "AAPL")
        // regular = 1789479000 ..< 1789502400
        #expect(q.marketState(now: Date(timeIntervalSince1970: 1_789_478_000)) == .preMarket)
        #expect(q.marketState(now: Date(timeIntervalSince1970: 1_789_490_000)) == .live)
        #expect(q.marketState(now: Date(timeIntervalSince1970: 1_789_502_400)) == .afterHours)
    }

    @Test func cryptoIsAlwaysLive() throws {
        let q = try YahooFinanceParser.quote(from: data(StockFixtures.btcDay), symbol: "BTC-USD")
        #expect(q.symbol == "BTC-USD")
        #expect(q.isCrypto)
        #expect(q.displayName == "Bitcoin USD")
        #expect(q.price == 75617.8)
        #expect(q.points.count == 24)
        #expect(q.marketState(now: Date(timeIntervalSince1970: 1_789_600_000)) == .live)
    }

    @Test func unknownSymbolIsNotFound() {
        #expect(throws: StockQuoteError.notFound(symbol: "NOTAREALTICKERXYZ", reason: "No data found, symbol may be delisted")) {
            try YahooFinanceParser.quote(from: data(StockFixtures.notFound), symbol: "NOTAREALTICKERXYZ")
        }
    }

    @Test func garbageIsMalformedNotACrash() {
        #expect(throws: StockQuoteError.malformed("not JSON")) {
            try YahooFinanceParser.quote(from: data("<html>"), symbol: "AAPL")
        }
        #expect(throws: StockQuoteError.malformed("no result")) {
            try YahooFinanceParser.quote(from: data(#"{"chart":{"result":[{"meta":{}}]}}"#), symbol: "AAPL")
        }
    }

    @Test func nullBarsAreSkippedInTheSparkline() throws {
        let json = #"{"chart":{"result":[{"meta":{"regularMarketPrice":10,"symbol":"X"},"timestamp":[1,2,3],"indicators":{"quote":[{"close":[9.5,null,10]}]}}]}}"#
        let q = try YahooFinanceParser.quote(from: data(json), symbol: "X")
        #expect(q.points.map(\.close) == [9.5, 10])
        #expect(q.previousClose == nil && q.change == nil)
        #expect(StockFormat.changeLine(q) == nil)
    }

    @Test func searchKeepsTradableInstrumentsOnly() throws {
        let hits = try YahooFinanceParser.searchHits(from: data(StockFixtures.searchApple))
        // Two stock futures in the fixture are dropped
        #expect(hits.map(\.symbol) == ["AAPL", "APLE", "AAPL.TO", "AAPX"])
        #expect(hits[0] == StockSearchHit(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", typeDisplay: "Equity"))
        #expect(hits[3].typeDisplay == "ETF")
        #expect(hits[0].entry.symbol == "AAPL" && hits[0].entry.name == "Apple Inc.")
    }
}

struct StockFormatTests {
    @Test func yahooStyleStrings() {
        #expect(StockFormat.price(331.34) == "331.34")
        #expect(StockFormat.price(1234.5) == "1,234.50")
        #expect(StockFormat.price(0.1234, hint: 4) == "0.1234")
        #expect(StockFormat.change(-1.74) == "-1.74")
        #expect(StockFormat.change(0) == "+0.00")
        #expect(StockFormat.percent(-0.5224) == "-0.52%")
        #expect(StockFormat.compact(31_420_574) == "31.42M")
        #expect(StockFormat.compact(39_603_904_512) == "39.60B")
        #expect(StockFormat.compact(1_234) == "1.23K")
        #expect(StockFormat.compact(999) == "999")
    }
}

struct WatchlistTests {
    private func entry(_ symbol: String) -> WatchlistEntry { WatchlistEntry(symbol: symbol, name: symbol) }

    @Test func addNormalizesDedupesAndCaps() {
        var list = Watchlist()
        let addedFirst = list.add(entry(" aapl "))
        #expect(addedFirst)
        #expect(list.symbols == ["AAPL"])
        let addedDuplicate = list.add(entry("AAPL"))
        #expect(!addedDuplicate)
        #expect(list.contains("aapl"))
        for i in 0..<Watchlist.maxEntries { list.add(entry("S\(i)")) }
        #expect(list.entries.count == Watchlist.maxEntries)
        let addedOverflow = list.add(entry("ONE-TOO-MANY"))
        #expect(!addedOverflow)
    }

    @Test func removeAndMove() {
        var list = Watchlist(entries: ["A", "B", "C", "D"].map(entry))
        list.remove("b")
        #expect(list.symbols == ["A", "C", "D"])
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)   // A to the end
        #expect(list.symbols == ["C", "D", "A"])
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)   // A back to the front
        #expect(list.symbols == ["A", "C", "D"])
        list.move(fromOffsets: IndexSet(integer: 9), toOffset: 0)   // out of range: no-op
        #expect(list.symbols == ["A", "C", "D"])
    }

    @Test func mergeIsAUnionInLocalOrder() {
        let local = Watchlist(entries: ["A", "C"].map(entry))
        let remote = Watchlist(entries: ["A", "B", "C", "D"].map(entry))
        let merged = Watchlist.merge(local: local, remote: remote)
        #expect(merged.symbols == ["A", "C", "B", "D"])   // local first, remote extras after, nothing lost
        #expect(Watchlist.merge(local: remote, remote: local).symbols == ["A", "B", "C", "D"])
    }

    @Test func roundTripsThroughTheDocumentCodec() throws {
        let list = Watchlist(entries: [WatchlistEntry(symbol: "aapl", name: "Apple Inc.", exchange: "NASDAQ",
                                                      addedAt: Date(timeIntervalSince1970: 1_700_000_000))])
        let encoded = try WidgetDocumentCodec.encode(list)
        #expect(try WidgetDocumentCodec.decode(Watchlist.self, from: encoded) == list)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""symbol":"AAPL""#))
    }
}

struct YahooFinanceClientTests {
    @Test func urlsEncodeTickersAndCarryTheRangeInterval() {
        #expect(YahooFinanceClient.chartURL(symbol: "aapl", range: .day).absoluteString
                == "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m&includePrePost=false")
        #expect(YahooFinanceClient.chartURL(symbol: "^GSPC", range: .fiveYears).absoluteString
                == "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?range=5y&interval=1wk&includePrePost=false")
        #expect(YahooFinanceClient.searchURL(query: "apple inc").absoluteString
                == "https://query1.finance.yahoo.com/v1/finance/search?q=apple%20inc&quotesCount=8&newsCount=0&listsCount=0")
    }

    @Test func batchFetchReturnsPerSymbolResults() async throws {
        let client = YahooFinanceClient(fetch: { url in
            let path = url.path
            if path.hasSuffix("/AAPL") { return Data(StockFixtures.aaplDay.utf8) }
            if path.hasSuffix("/BTC-USD") { return Data(StockFixtures.btcDay.utf8) }
            return Data(StockFixtures.notFound.utf8)
        }, concurrency: 2)
        let results = await client.quotes(symbols: ["aapl", "BTC-USD", "NOPE", "AAPL"])   // duplicate collapses
        #expect(results.count == 3)
        #expect((try? results["AAPL"]?.get())?.price == 331.34)
        #expect((try? results["BTC-USD"]?.get())?.isCrypto == true)
        if case .failure(let error)? = results["NOPE"] {
            #expect((error as? StockQuoteError) == .notFound(symbol: "NOPE", reason: "No data found, symbol may be delisted"))
        } else {
            Issue.record("NOPE should have failed")
        }
        #expect(try await client.search("   ").isEmpty)
    }
}

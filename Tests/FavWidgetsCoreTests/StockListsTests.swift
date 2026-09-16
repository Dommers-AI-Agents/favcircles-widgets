import Testing
import Foundation
@testable import FavWidgetsCore

/// Named lists inside My Stocks, and the migration from the flat shape.
struct StockListsTests {
    private func entry(_ s: String) -> WatchlistEntry { WatchlistEntry(symbol: s, name: s, exchange: nil, addedAt: Date(timeIntervalSince1970: 0)) }

    @Test func flatDocumentsBecomeOneMyStocksList() throws {
        let legacy = Data(#"{"entries":[{"symbol":"AAPL","name":"Apple","addedAt":0},{"symbol":"BTC-USD","name":"Bitcoin","addedAt":0}]}"#.utf8)
        let decoded = try JSONDecoder().decode(Watchlist.self, from: legacy)
        #expect(decoded.lists.count == 1)
        #expect(decoded.lists[0].name == "My Stocks")
        #expect(decoded.symbols == ["AAPL", "BTC-USD"])
        let empty = try JSONDecoder().decode(Watchlist.self, from: Data(#"{"entries":[]}"#.utf8))
        #expect(empty.lists.isEmpty && empty.entries.isEmpty)
    }

    @Test func listsRoundTripAndEncodeOnlyLists() throws {
        var w = Watchlist()
        let tech = w.addList(named: "Tech")!
        let crypto = w.addList(named: " Crypto ")!
        let added1 = w.add(entry("AAPL"), to: tech), added2 = w.add(entry("BTC-USD"), to: crypto)
        #expect(added1 && added2)
        let data = try JSONEncoder().encode(w)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"lists\"") && json.contains("\"entries\""))   // both shapes on the wire
        let back = try JSONDecoder().decode(Watchlist.self, from: data)
        #expect(back == w)
        #expect(back.lists.map(\.name) == ["Tech", "Crypto"])
    }

    @Test func addRemoveMoveArePerList() {
        var w = Watchlist()
        let a = w.addList(named: "A")!, b = w.addList(named: "B")!
        let x = w.add(entry("X"), to: a), y = w.add(entry("Y"), to: a), z = w.add(entry("Z"), to: a)
        #expect(x && y && z)
        let xInB = w.add(entry("X"), to: b)               // same symbol allowed in another list
        #expect(xInB)
        let dup = w.add(entry("x"), to: a)                // duplicate within a list, case-insensitive
        #expect(!dup)
        #expect(w.symbols == ["X", "Y", "Z"])             // deduped across lists
        w.move(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: a)
        #expect(w.list(id: a)!.symbols == ["Z", "X", "Y"])
        #expect(w.list(id: b)!.symbols == ["X"])
        w.remove("X", from: a)
        #expect(w.list(id: a)!.symbols == ["Z", "Y"] && w.list(id: b)!.symbols == ["X"])
        w.remove("X")
        #expect(!w.contains("X"))
        w.renameList(b, to: "Bees"); w.deleteList(a)
        #expect(w.lists.map(\.name) == ["Bees"])
        let blank = w.addList(named: "   ")
        #expect(blank == nil)
    }

    @Test func legacyApiStillTargetsTheFirstList() {
        var w = Watchlist()
        let first = w.add(entry("AAPL"))                  // creates "My Stocks"
        #expect(first)
        #expect(w.lists.map(\.name) == ["My Stocks"])
        let second = w.add(entry("MSFT"))
        #expect(second)
        w.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(w.entries.map(\.symbol) == ["MSFT", "AAPL"])
    }

    @Test func mergeIsPerListUnionAndAppendsUnknownLists() {
        var local = Watchlist(); let id = local.addList(named: "Tech")!
        local.add(entry("AAPL"), to: id)
        var remote = Watchlist(lists: [StockList(id: id, name: "Tech", entries: [entry("AAPL"), entry("NVDA")])])
        remote.addList(named: "Crypto")
        let merged = Watchlist.merge(local: local, remote: remote)
        #expect(merged.lists.count == 2)
        #expect(merged.list(id: id)!.symbols == ["AAPL", "NVDA"])
        #expect(merged.lists[1].name == "Crypto")
    }
}

struct StockListCollapseAndOrderTests {
    @Test func listsWithoutTheCollapsedKeyDecodeExpanded() throws {
        let json = Data(#"{"lists":[{"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","name":"Tech","entries":[]}]}"#.utf8)
        let w = try JSONDecoder().decode(Watchlist.self, from: json)
        #expect(w.lists.count == 1 && w.lists[0].isCollapsed == false)
        var toggled = w
        toggled.setCollapsed(true, listId: w.lists[0].id)
        let back = try JSONDecoder().decode(Watchlist.self, from: JSONEncoder().encode(toggled))
        #expect(back.lists[0].isCollapsed)
    }

    @Test func listsReorderByDragAndByNeighbourSwap() {
        var w = Watchlist()
        let a = w.addList(named: "A")!, b = w.addList(named: "B")!, c = w.addList(named: "C")!
        w.moveLists(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(w.lists.map(\.id) == [c, a, b])
        w.moveList(b, by: -1)
        #expect(w.lists.map(\.id) == [c, b, a])
        w.moveList(c, by: -1)                       // already first: no-op
        #expect(w.lists.map(\.id) == [c, b, a])
        w.moveList(a, by: 1)                        // already last: no-op
        #expect(w.lists.map(\.id) == [c, b, a])
    }
}

import Testing
import Foundation
@testable import FavWidgetsCore

@MainActor
struct WidgetStateControllerTests {
    private func makeController(store: InMemoryWidgetDataStore, debounce: Duration = .milliseconds(20)) -> WidgetStateController<WaterLog> {
        WidgetStateController<WaterLog>(documentId: "water", schemaVersion: 1, store: store, debounce: debounce)
    }

    @Test func loadsOnceAndStartsEmpty() async {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store)
        await c.loadIfNeeded()
        await c.loadIfNeeded()
        #expect(store.loadCount == 1)
        #expect(c.hasLoaded && c.model == .empty && c.syncState == .idle)
    }

    @Test func coalescesBurstsIntoOneSave() async throws {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store)
        await c.loadIfNeeded()
        let day = DayKey(rawValue: "2026-09-13")
        for _ in 0..<5 { c.update { $0.add(1, on: day) } }
        try await Task.sleep(for: .milliseconds(150))
        #expect(store.saveCount == 1)
        #expect(c.model.cups(on: day) == 5)
        #expect(store.document(id: "water")?.version == 1)
        let stored = try WidgetDocumentCodec.decode(WaterLog.self, from: store.document(id: "water")!.payload)
        #expect(stored.cups(on: day) == 5)
    }

    @Test func flushSavesImmediately() async throws {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store, debounce: .seconds(30))
        await c.loadIfNeeded()
        c.update { $0.goalCups = 10 }
        await c.flush()
        #expect(store.saveCount == 1)
        #expect(c.syncState == .idle)
    }

    @Test func mergesOnConflictAndRetriesOnce() async throws {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store, debounce: .seconds(30))
        await c.loadIfNeeded()
        let day = DayKey(rawValue: "2026-09-13")
        // Another device saved first.
        var other = WaterLog(); other.add(3, on: day)
        store.overwrite(id: "water", payload: try WidgetDocumentCodec.encode(other))
        c.update { $0.add(1, on: day) }
        await c.flush()
        #expect(c.syncState == .idle)
        #expect(c.model.cups(on: day) == 3)          // per-day max wins
        #expect(store.document(id: "water")?.version == 2)
        #expect(store.saveCount == 2)
    }

    @Test func secondConflictStopsRetrying() async throws {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store, debounce: .seconds(30))
        await c.loadIfNeeded()
        c.update { $0.goalCups = 9 }
        store.nextSaveError = .conflict(server: WidgetDocument(version: 5, payload: try WidgetDocumentCodec.encode(WaterLog()), schemaVersion: 1))
        // The retry hits the real store, whose version is 0 ≠ 5 → conflict again.
        await c.flush()
        #expect(c.syncState == .conflict)
        #expect(c.model.goalCups == 9)
    }

    @Test func networkFailureKeepsEditPending() async throws {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store, debounce: .seconds(30))
        await c.loadIfNeeded()
        c.update { $0.goalCups = 11 }
        store.nextSaveError = .network("offline")
        await c.flush()
        #expect(c.syncState == .error("offline"))
        await c.flush()
        #expect(c.syncState == .idle && store.document(id: "water")?.version == 1)
    }

    @Test func oversizedPayloadNeverDropsData() async {
        let store = InMemoryWidgetDataStore()
        let c = makeController(store: store, debounce: .seconds(30))
        await c.loadIfNeeded()
        c.update { log in
            for i in 0..<9000 { log.months[MonthKey(year: 2000 + i / 12, month: i % 12 + 1)] = Array(repeating: 8, count: 31) }
        }
        await c.flush()
        if case .error = c.syncState {} else { Issue.record("expected error state") }
        #expect(store.saveCount == 0)
        #expect(c.model.months.count == 9000)
    }

    @Test func adoptIgnoresOlderVersions() async throws {
        let store = InMemoryWidgetDataStore()
        var saved = WaterLog(); saved.goalCups = 6
        store.overwrite(id: "water", payload: try WidgetDocumentCodec.encode(saved))   // v1
        let c = makeController(store: store)
        await c.loadIfNeeded()
        #expect(c.model.goalCups == 6)
        var older = WaterLog(); older.goalCups = 3
        c.adopt(WidgetDocument(version: 0, payload: try WidgetDocumentCodec.encode(older), schemaVersion: 1))
        #expect(c.model.goalCups == 6)
    }
}

struct CachedStoreTests {
    @Test func fallsBackToDiskWhenOffline() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("favwidgets-test-\(UUID().uuidString)")
        let inner = InMemoryWidgetDataStore()
        let cached = CachedWidgetDataStore(wrapping: inner, directory: dir)
        let doc = WidgetDocument(version: 0, payload: try WidgetDocumentCodec.encode(WaterLog()), schemaVersion: 1)
        let saved = try await cached.save(id: "water", document: doc)
        #expect(saved.version == 1)
        #expect(cached.cached(ids: ["water", "habits"]).keys.sorted() == ["water"])
        inner.loadError = .network("offline")
        let offline = try await cached.load(ids: ["water"])
        #expect(offline["water"]?.version == 1)
        let single = try await cached.load(id: "water")
        #expect(single?.version == 1)
        cached.clear()
        #expect(cached.cached(ids: ["water"]).isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }
}

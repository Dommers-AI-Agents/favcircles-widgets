import Testing
import Foundation
@testable import FavWidgets

/// The Events bug (2026-10-12): the card started loading, the full view
/// waited on it, the card's view went away, and the full view showed
/// "cancelled" with no events.
@MainActor
struct RemoteStoreTests {
    final class Store: RemoteStore { var items: [String] = [] }

    @Test func aCallerLeavingDoesNotCancelTheLoadForTheOthers() async throws {
        let store = Store()
        let card = Task { @MainActor in
            await store.load {
                try await Task.sleep(nanoseconds: 200_000_000)
                store.items = ["Party Bus"]
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        let fullView = Task { @MainActor in await store.loadIfNeeded { store.items = ["never runs: shares the load"] } }
        card.cancel()
        await fullView.value
        #expect(store.items == ["Party Bus"])
        #expect(store.loadError == nil)
        #expect(store.hasLoaded)
    }

    @Test func aCancelledFetchIsNotAnError() async {
        let store = Store()
        await store.load { throw URLError(.cancelled) }
        #expect(store.loadError == nil)
        #expect(!store.hasLoaded)
    }

    @Test func aRealFailureReadsAsAnAction() async {
        let store = Store()
        await store.load { throw URLError(.notConnectedToInternet) }
        #expect(store.loadError == "Couldn't connect. Pull down to try again.")
    }
}

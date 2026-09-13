import Testing
import Foundation
@testable import FavWidgets
@testable import FavWidgetsCore

@MainActor
struct NextBarRoundsTests {
    private let sample = """
    {"success":true,"rounds":[{"id":"r1","hostId":"u1","hostName":"Wes","status":"open","winnerPlaceId":null,
      "createdAt":"2026-09-13T20:00:00.000Z","expiresAt":"2026-09-13T23:00:00.000Z","closedAt":null,
      "participants":[{"id":"u1","name":"Wes","voted":true},{"id":"u2","name":"Ana","voted":false}],
      "options":[{"placeId":"p1","name":"Dive","address":null,"source":"mine","savers":["You","Ana"],"distanceMeters":400,"lat":40.7,"lng":-73.9,"isGlobal":true,"votes":1,"voters":["Wes"]},
                 {"placeId":"p2","name":"Rooftop","source":"connection","savers":["Ana"],"distanceMeters":900,"lat":40.71,"lng":-73.91,"isGlobal":true,"votes":0,"voters":[]}],
      "myVote":"p1","isHost":true}]}
    """

    @Test func listsAndDecodesRounds() async throws {
        let host = MockWidgetHost()
        host.apiResponses["GET widgets/nextbar/rounds"] = Data(sample.utf8)
        let store = NextBarRoundsStore(host: host)
        await store.refresh()
        #expect(store.rounds.count == 1)
        let round = try #require(store.rounds.first)
        #expect(round.isOpen && round.isHost && round.votedCount == 1 && round.myVote == "p1")
        #expect(round.options.first?.savers == ["You", "Ana"])
        #expect(store.openRounds.count == 1 && store.recentResults.isEmpty)
    }

    @Test func surfacesApiErrors() async {
        let host = MockWidgetHost()
        let store = NextBarRoundsStore(host: host)
        await store.refresh()
        #expect(store.errorMessage != nil && store.hasLoaded)
        #expect(host.apiRequests.first?.path == "widgets/nextbar/rounds")
    }
}

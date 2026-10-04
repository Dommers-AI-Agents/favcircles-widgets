import Testing
import Foundation
@testable import FavWidgetsCore

struct EventModelsTests {
    private let json = #"""
    {"event":{"id":"e1","name":"Party Bus","emoji":"🚌","hostId":"wes","hostName":"Wesley","isHost":true,"joinOpen":true,
      "createdAt":"2026-10-04T20:00:00Z","photoCount":2,"placeCount":1,
      "members":[{"id":"wes","name":"Wesley","avatarUrl":null,"isHost":true},{"id":"sal","name":"Sal","avatarUrl":"https://x/a.jpg","isHost":false}],
      "inviteUrl":"https://api.favcircles.com/app/event/abcdefghijklmnopqrst","myCircleId":null},
     "photos":[{"id":"p1","imageUrl":"https://x/1.jpg","uploaderId":"sal","uploaderName":"Sal","caption":"","createdAt":"2026-10-04T21:00:00Z","likeCount":3,"likedByMe":true,"canDelete":false}],
     "places":[{"id":"pl1","name":"Midnight Diner","address":"115 Graham St","lat":35.22,"lng":-80.84,"category":"restaurant","taggedById":"sal","taggedByName":"Sal","createdAt":null,"savedCount":1,"savedByMe":false}]}
    """#

    @Test func decodesTheServerShape() throws {
        let detail = try JSONDecoder().decode(EventDetail.self, from: Data(json.utf8))
        #expect(detail.event.members.count == 2 && detail.event.isHost)
        #expect(detail.event.inviteURL?.absoluteString.hasSuffix("abcdefghijklmnopqrst") == true)
        #expect(detail.photos.first?.likedByMe == true)
        #expect(detail.places.first?.name == "Midnight Diner")
    }

    @Test func copy() throws {
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(json.utf8)).event
        #expect(EventCopy.memberCount(1) == "Just you so far")
        #expect(EventCopy.memberCount(12) == "12 people")
        #expect(EventCopy.inviteText(event).contains(event.inviteUrl))
        #expect(EventCopy.joinedMessage(name: "Party Bus", coinCredited: true).contains("FavCoin"))
        #expect(EventCopy.uploadProgress(done: 0, total: 1) == "Adding your photo…")
        #expect(EventCopy.uploadProgress(done: 2, total: 8) == "Adding 3 of 8…")
        #expect(EventCopy.notConnected(event, myId: "wes", connectedIds: []).map(\.id) == ["sal"])
        #expect(EventCopy.notConnected(event, myId: "wes", connectedIds: ["sal"]).isEmpty)
    }
}

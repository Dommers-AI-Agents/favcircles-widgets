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

struct EventInviteCopyTests {
    @Test func inviteButtonNeverSaysZero() {
        #expect(EventCopy.inviteButton(selected: 0) == "Invite")
        #expect(EventCopy.inviteButton(selected: 3) == "Invite 3")
    }

    @Test func invitedListDecodesAndIsOptional() throws {
        let base = #"{"id":"e1","name":"Party Bus","emoji":"🚌","hostId":"wes","hostName":"Wesley","isHost":true,"joinOpen":true,"createdAt":null,"photoCount":0,"placeCount":0,"members":[],"inviteUrl":"https://x/app/event/t","myCircleId":null"#
        let old = try JSONDecoder().decode(EventSummary.self, from: Data((base + "}").utf8))
        #expect(old.invitedPeople.isEmpty)
        let new = try JSONDecoder().decode(EventSummary.self, from: Data((base + #","invited":[{"id":"amy","name":"Amy"}]}"#).utf8))
        #expect(new.invitedPeople.map(\.name) == ["Amy"])
    }
}

struct EventArchiveTests {
    @Test func archivedFlagsDecodeAndDefaultOff() throws {
        let base = #"{"id":"e1","name":"Party Bus","emoji":"🚌","hostId":"wes","hostName":"Wesley","isHost":true,"joinOpen":false,"createdAt":null,"photoCount":0,"placeCount":0,"members":[],"inviteUrl":"https://x/app/event/t","myCircleId":null"#
        let old = try JSONDecoder().decode(EventSummary.self, from: Data((base + "}").utf8))
        #expect(!old.isArchived && !old.isArchivedForEveryone)
        let archived = try JSONDecoder().decode(EventSummary.self, from: Data((base + #","archived":true,"archivedForEveryone":true}"#).utf8))
        #expect(archived.isArchived && archived.isArchivedForEveryone)
    }
}

struct EventNotificationNudgeTests {
    @Test func nudgeByPermission() {
        #expect(EventCopy.notificationNudge(.allowed, eventName: "Party Bus") == nil)
        #expect(EventCopy.notificationNudge(.notDetermined, eventName: "Party Bus")?.button == "Turn on notifications")
        #expect(EventCopy.notificationNudge(.denied, eventName: "Party Bus")?.button == "Open Settings")
    }

    @Test func coordinatorSummary() {
        #expect(EventCopy.pushOffSummary(count: 0) == nil)
        #expect(EventCopy.pushOffSummary(count: 1)?.hasPrefix("1 person") == true)
        #expect(EventCopy.pushOffSummary(count: 3)?.hasPrefix("3 people") == true)
    }
}

import Testing
import Foundation
@testable import FavWidgetsCore

struct EventTogetherTests {
    private let json = #"""
    {"id":"e1","name":"Party Bus","emoji":"🚌","hostId":"wes","hostName":"Wes","isHost":false,"joinOpen":true,
     "photoCount":2,"placeCount":0,"inviteUrl":"https://x/app/event/t","myCircleId":null,"createdAt":null,
     "members":[{"id":"wes","name":"Wes","avatarUrl":null,"isHost":true},{"id":"sal","name":"Sal","avatarUrl":null,"isHost":false},
                {"id":"brit","name":"Brit","avatarUrl":null,"isHost":false}],
     "endedAt":null,
     "challenges":[{"id":"c1","text":"Group selfie","emoji":"🤳"},{"id":"c2","text":"Best dance move","emoji":"💃"}],
     "rollCall":{"id":"rc","startedAt":"t","startedByName":"Wes","hereIds":["wes","sal"],"imHere":true,
                 "locations":[{"userId":"sal","lat":35.2,"lng":-80.8,"at":"t"}]}}
    """#

    @Test func decodesTheNewEventFieldsAndOlderServersStillDecode() throws {
        let event = try JSONDecoder().decode(EventSummary.self, from: Data(json.utf8))
        #expect(event.challengeList.map(\.id) == ["c1", "c2"])
        #expect(event.rollCall?.hereIds == ["wes", "sal"])
        #expect(!event.hasEnded)
        let old = #"{"id":"e","name":"n","emoji":"🚌","hostId":"h","hostName":"H","isHost":true,"joinOpen":true,"photoCount":0,"placeCount":0,"inviteUrl":"u","myCircleId":null,"createdAt":null,"members":[]}"#
        let legacy = try JSONDecoder().decode(EventSummary.self, from: Data(old.utf8))
        #expect(legacy.challengeList.isEmpty && legacy.rollCall == nil && !legacy.hasEnded)
    }

    @Test func rollCallSaysWhoIsMissing() throws {
        let event = try JSONDecoder().decode(EventSummary.self, from: Data(json.utf8))
        let rc = try #require(event.rollCall)
        #expect(EventTogether.missing(rc, members: event.members).map(\.name) == ["Brit"])
        #expect(EventTogether.rollCallLine(rc, memberCount: 3) == "2 of 3 here")
        #expect(EventTogether.rollCallLine(rc, memberCount: 2) == "Everyone's here 🙌")
    }

    @Test func challengesDoneAreYourOwnPhotos() {
        let photos = [
            EventPhoto(id: "p1", imageUrl: "a", uploaderId: "sal", uploaderName: "Sal", caption: "", createdAt: nil, likeCount: 0, likedByMe: false, canDelete: true, challengeId: "c1"),
            EventPhoto(id: "p2", imageUrl: "b", uploaderId: "wes", uploaderName: "Wes", caption: "", createdAt: nil, likeCount: 0, likedByMe: false, canDelete: false, challengeId: "c2"),
            EventPhoto(id: "p3", imageUrl: "c", uploaderId: "sal", uploaderName: "Sal", caption: "", createdAt: nil, likeCount: 0, likedByMe: false, canDelete: true)
        ]
        #expect(EventTogether.doneChallengeIds(photos: photos, userId: "sal") == ["c1"])
    }

    @Test func recapDecodes() throws {
        let r = #"{"eventId":"e1","name":"Party Bus","emoji":"🚌","startedAt":"2026-10-06T20:30:00Z","endedAt":null,"memberCount":3,"memberNames":["Wes","Sal","Brit"],"photoCount":3,"placeCount":1,"topPhotos":[{"imageUrl":"b","uploaderName":"Sal","likes":2}],"photoOfTheNight":{"imageUrl":"b","uploaderName":"Sal","likes":2},"topPhotographer":{"name":"Sal","photos":2},"places":[{"name":"Midnight Diner","lat":35.22,"lng":-80.84}],"challenges":{"total":2,"done":1},"topShoutout":null,"topSong":{"title":"Mr. Brightside","artist":null,"votes":3}}"#
        let recap = try JSONDecoder().decode(EventRecap.self, from: Data(r.utf8))
        #expect(recap.photoOfTheNight?.likes == 2 && recap.topSong?.title == "Mr. Brightside" && recap.topShoutout == nil)
    }

    @Test func photosUseTheirPreviewInTheGridAndOldOnesStillWork() throws {
        let with = #"{"id":"p","imageUrl":"full","thumbUrl":"thumb","uploaderId":"u","uploaderName":"U","caption":"","createdAt":null,"likeCount":0,"likedByMe":false,"canDelete":false}"#
        let without = #"{"id":"p","imageUrl":"full","uploaderId":"u","uploaderName":"U","caption":"","createdAt":null,"likeCount":0,"likedByMe":false,"canDelete":false}"#
        #expect(try JSONDecoder().decode(EventPhoto.self, from: Data(with.utf8)).gridURL == "thumb")
        #expect(try JSONDecoder().decode(EventPhoto.self, from: Data(without.utf8)).gridURL == "full")
    }
}

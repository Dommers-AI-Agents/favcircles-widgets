import Foundation
import Testing
@testable import FavWidgetsCore

/// Clubs (Wes, 2026-10-21): the server's shapes, and the words the screens use.
struct ClubModelsTests {
    private let ny = TimeZone(identifier: "America/New_York")!

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func decodesTheClubPage() throws {
        let json = """
        {"club":{"id":"c1","name":"Charlotte Run Club","emoji":"🏃","kind":"run","memberCount":12,"myRole":"organizer","muted":false,
         "description":"Easy miles, then coffee.","homeSpot":{"name":"Freedom Park","lat":35.19,"lng":-80.84},
         "timezone":"America/New_York","ownerId":"u0","ownerName":"Wes","joinOpen":true,
         "inviteLink":"https://api.favcircles.com/app/club/abcdefghijklmnop1234","scheduleLine":"Saturdays 7 AM",
         "schedule":[{"id":"m1","weekday":6,"time":"07:00","title":"Long run","spot":null,"notes":"6 miles"}],
         "events":[{"id":"e1","title":"Turkey Trot","startsAt":"2026-11-27T13:00:00.000Z","spot":{"name":"Uptown"},"notes":null}],
         "members":[{"userId":"u0","name":"Wes Sgroi","avatarUrl":null,"role":"owner","joinedAt":"2026-10-21T12:00:00.000Z"}],
         "upcoming":[{"key":"m_m1_2026-10-25","kind":"meetup","title":"Long run","startsAt":"2026-10-25T11:00:00.000Z",
           "spot":{"name":"Freedom Park"},"notes":"6 miles","going":[{"userId":"u1","name":"Ana Ruiz","avatarUrl":null}],
           "notGoingCount":1,"myRsvp":null}],
         "bulletin":[{"id":"p1","kind":"bulletin","authorId":"u0","authorName":"Wes","authorAvatar":null,"text":"Route change",
           "photoUrl":null,"createdAt":"2026-10-21T12:00:00Z","replyCount":2,"reactions":[{"emoji":"👍","count":3,"mine":true}],"canDelete":true}],
         "boardPreview":[], "futureField": 1}}
        """
        struct Wrap: Decodable { let club: Club }
        let club = try WidgetJSON.decode(Wrap.self, from: Data(json.utf8)).club
        #expect(club.kind == .run && club.myRole == .organizer && club.canOrganize && !club.isOwner)
        #expect(club.schedule.first?.weekday == 6)
        #expect(club.events.first?.title == "Turkey Trot")
        #expect(club.upcoming.first?.going.first?.name == "Ana Ruiz")
        #expect(club.upcoming.first?.myRsvp == nil)
        #expect(club.bulletin.first?.myReaction == "👍")
        #expect(club.inviteURL?.absoluteString.hasSuffix("abcdefghijklmnop1234") == true)
        #expect(club.timeZone.identifier == "America/New_York")
        #expect(club.summary.next?.key == "m_m1_2026-10-25")
    }

    @Test func unknownKindsAndRolesStillDecode() throws {
        let json = #"{"id":"c","name":"X","kind":"pickleball","memberCount":1,"myRole":"captain"}"#
        let summary = try WidgetJSON.decode(ClubSummary.self, from: Data(json.utf8))
        #expect(summary.kind == .other && summary.myRole == .member && summary.emoji == "🤝")
    }

    @Test func clockAndScheduleLines() {
        #expect(ClubCopy.clock("07:00") == "7 AM")
        #expect(ClubCopy.clock("18:30") == "6:30 PM")
        #expect(ClubCopy.clock("00:05") == "12:05 AM")
        #expect(ClubCopy.clock("12:00") == "12 PM")
        let meetups = [ClubMeetup(id: "b", weekday: 3, time: "18:30", title: "Track"),
                       ClubMeetup(id: "a", weekday: 6, time: "07:00", title: "Long run")]
        #expect(ClubCopy.scheduleLine(meetups) == "Wednesdays 6:30 PM · Saturdays 7 AM")
        #expect(ClubCopy.scheduleLine(meetups, server: "From the server") == "From the server")
        #expect(ClubCopy.scheduleLine([]) == nil)
    }

    @Test func occurrenceAndRelativeLines() {
        let sat = date("2026-10-24T11:00:00Z") // Saturday 7 AM in New York (EDT)
        #expect(ClubCopy.occurrenceLine(sat, timeZone: ny) == "Sat, Oct 24 · 7 AM")
        #expect(ClubCopy.relative(sat, now: date("2026-10-23T14:00:00Z"), timeZone: ny) == "Tomorrow 7 AM")
        #expect(ClubCopy.relative(sat, now: date("2026-10-24T09:00:00Z"), timeZone: ny) == "Today 7 AM")
        #expect(ClubCopy.relative(sat, now: date("2026-10-21T14:00:00Z"), timeZone: ny) == "Sat 7 AM")
        // After the clocks change (EST): Friday 6:30 PM
        #expect(ClubCopy.relative(date("2026-11-20T23:30:00Z"), now: sat, timeZone: ny) == "Fri, Nov 20 · 6:30 PM")
    }

    @Test func goingLines() {
        let ana = ClubPerson(userId: "a", name: "Ana Ruiz"), joe = ClubPerson(userId: "j", name: "Joe Sgroi")
        let me = ClubPerson(userId: "me", name: "Wes Sgroi")
        let more = (1...4).map { ClubPerson(userId: "x\($0)", name: "P\($0)") }
        #expect(ClubCopy.goingLine([]) == "Nobody's said yet")
        #expect(ClubCopy.goingLine([ana]) == "Ana going")
        #expect(ClubCopy.goingLine([ana, joe]) == "Ana and Joe going")
        #expect(ClubCopy.goingLine([ana, joe] + more) == "Ana, Joe and 4 others going")
        #expect(ClubCopy.goingLine([ana, me], meId: "me") == "You and Ana going")
    }

    @Test func optimisticRsvp() {
        let me = ClubPerson(userId: "me", name: "Wes")
        let occ = ClubOccurrence(key: "k", kind: "meetup", title: "Run", startsAt: Date(), going: [ClubPerson(userId: "a", name: "Ana")], notGoingCount: 1)
        let going = occ.with(myRsvp: .going, me: me)
        #expect(going.going.map(\.userId) == ["me", "a"] && going.myRsvp == .going && going.notGoingCount == 1)
        let notGoing = going.with(myRsvp: .not, me: me)
        #expect(notGoing.going.map(\.userId) == ["a"] && notGoing.notGoingCount == 2)
        let cleared = notGoing.with(myRsvp: nil, me: me)
        #expect(cleared.notGoingCount == 1 && cleared.myRsvp == nil)
    }

    @Test func soonestAcrossClubs() {
        let now = date("2026-10-21T12:00:00Z")
        let a = ClubSummary(id: "a", name: "A", emoji: "🏃", kind: .run, memberCount: 3, myRole: .member,
                            next: ClubOccurrence(key: "1", kind: "meetup", title: "", startsAt: date("2026-10-25T11:00:00Z")))
        let b = ClubSummary(id: "b", name: "B", emoji: "📚", kind: .book, memberCount: 3, myRole: .member,
                            next: ClubOccurrence(key: "2", kind: "meetup", title: "", startsAt: date("2026-10-22T23:00:00Z")))
        let none = ClubSummary(id: "c", name: "C", emoji: "🤝", kind: .other, memberCount: 1, myRole: .owner)
        #expect(ClubCopy.soonest([a, b, none], now: now)?.club.id == "b")
        #expect(ClubCopy.soonest([none], now: now) == nil)
    }

    @Test func pastedLinksBecomeTokens() {
        #expect(ClubCopy.token(fromPasted: "https://api.favcircles.com/app/club/AbCdEfGh12345678_x") == "AbCdEfGh12345678_x")
        #expect(ClubCopy.token(fromPasted: "  AbCdEfGh12345678  ") == "AbCdEfGh12345678")
        #expect(ClubCopy.token(fromPasted: "circles://club/AbCdEfGh12345678") == "AbCdEfGh12345678")
        #expect(ClubCopy.token(fromPasted: "https://api.favcircles.com/app/event/AbCdEfGh12345678") == nil)
        #expect(ClubCopy.token(fromPasted: "short") == nil)
        #expect(ClubCopy.token(fromPasted: "") == nil)
    }

    @Test func remindersAnHourBeforeAndNotInQuietHours() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ny
        let occ = ClubOccurrence(key: "k", kind: "meetup", title: "", startsAt: date("2026-10-25T11:00:00Z"))
        let at = ClubCopy.reminderDate(for: occ)
        #expect(at == date("2026-10-25T10:00:00Z"))   // 6 AM NY
        let quiet = WidgetQuietHours(start: "22:00", end: "07:00")
        #expect(ClubCopy.reminderIsQuiet(at, quietHours: quiet, calendar: cal))
        #expect(!ClubCopy.reminderIsQuiet(at, quietHours: nil, calendar: cal))
        #expect(!ClubCopy.reminderIsQuiet(at, quietHours: WidgetQuietHours(start: "22:00", end: "05:00"), calendar: cal))
    }
}

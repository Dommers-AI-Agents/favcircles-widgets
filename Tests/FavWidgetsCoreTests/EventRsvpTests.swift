import Testing
import Foundation
@testable import FavWidgetsCore

/// Email invites + RSVPs (2026-11-02): the server's new shapes decode (and
/// old servers still do), and the words around replies.
struct EventRsvpTests {
    private let eventJSON = #"""
    {"id":"e1","name":"Bday","emoji":"🎂","hostId":"wes","hostName":"Wes","isHost":true,"joinOpen":true,"createdAt":null,
     "photoCount":0,"placeCount":0,"members":[{"id":"wes","name":"Wes","avatarUrl":null,"isHost":true}],
     "inviteUrl":"https://api.favcircles.com/app/event/abcdefghijklmnopqrst","myCircleId":null,
     "startsAt":"2026-11-15T00:00:00.000Z","endsAt":null,"timezone":"America/New_York",
     "location":{"name":"Pasta & Provisions","address":"1528 Central Ave","lat":35.2,"lng":-80.8},"details":"Dress warm",
     "whenText":"Saturday, November 14 · 7:00 PM EST","whereText":"Pasta & Provisions, 1528 Central Ave",
     "calendarUrl":"https://api.favcircles.com/calendar/event/abc.ics",
     "myRsvp":{"rsvp":"maybe","adults":2,"kids":1,"note":""},
     "rsvpCounts":{"yes":{"replies":2,"people":3},"maybe":{"replies":1,"people":3},"no":{"replies":1,"people":0},"pending":{"replies":4,"people":4}},
     "guestCount":5}
    """#

    @Test func theNewFieldsDecode() throws {
        let event = try JSONDecoder().decode(EventSummary.self, from: Data(eventJSON.utf8))
        #expect(event.whenText == "Saturday, November 14 · 7:00 PM EST")
        #expect(event.location?.coordinate?.latitude == 35.2)
        #expect(event.myRsvp?.rsvp == .maybe)
        #expect(event.rsvpCounts?.yes.people == 3)
        #expect(event.startDate == EventTimes.parse("2026-11-15T00:00:00Z"))
        #expect(event.emailGuestCount == 5)
    }

    @Test func olderServersStillDecode() throws {
        let old = #"{"id":"e1","name":"Bus","emoji":"🚌","hostId":"w","hostName":"W","isHost":false,"joinOpen":true,"photoCount":0,"placeCount":0,"members":[],"inviteUrl":"x","myCircleId":null}"#
        let event = try JSONDecoder().decode(EventSummary.self, from: Data(old.utf8))
        #expect(event.myRsvp == nil && event.rsvpCounts == nil && event.whenText == nil)
    }

    @Test func anUnknownReplyReadsAsNoReply() throws {
        let guest = try JSONDecoder().decode(EventGuest.self, from: Data(#"{"id":"g","kind":"email","name":"","rsvp":"later","email":"a@b.co"}"#.utf8))
        #expect(guest.rsvp == .pending)
        #expect(guest.displayName == "a@b.co")
    }

    @Test func summaryCountsPeople() {
        let counts = EventRsvpCounts(yes: .init(replies: 2, people: 5), maybe: .init(replies: 0, people: 0),
                                     no: .init(replies: 1, people: 0), pending: .init(replies: 3, people: 3))
        #expect(EventRsvpCopy.summary(counts) == "5 going · 1 can't go · 3 no reply")
        #expect(EventRsvpCopy.summary(nil) == nil)
        let none = EventRsvpCounts(yes: .init(replies: 0, people: 0), maybe: .init(replies: 0, people: 0),
                                   no: .init(replies: 0, people: 0), pending: .init(replies: 0, people: 0))
        #expect(EventRsvpCopy.summary(none) == nil)
    }

    @Test func pastedAddressesAreFound() {
        let pasted = "Sam Smith <Sam@Example.com>, bea@y.org; bea@y.org\nnot-an-email@ x@y z@q.c ok@ok.io"
        let out = EventRsvpCopy.parseEmails(pasted)
        #expect(out.emails == ["sam@example.com", "bea@y.org", "ok@ok.io"])
        #expect(out.invalid == ["not-an-email@", "x@y", "z@q.c"])
    }

    @Test func repliesInWords() {
        #expect(EventRsvpCopy.myReply(EventMyRsvp(rsvp: .yes)) == "You're going")
        #expect(EventRsvpCopy.myReply(EventMyRsvp(rsvp: .maybe, adults: 2, kids: 1)) == "You might go (2 adults, 1 kid)")
        #expect(EventRsvpCopy.myReply(EventMyRsvp(rsvp: .no)) == "You can't make it")
        #expect(EventRsvpCopy.partySize(adults: 1, kids: 0) == "")
        #expect(EventRsvpCopy.inviteEmailsButton(1) == "Send 1 invite")
        #expect(EventRsvpCopy.invitesSent(sent: 3, already: 1, invalid: 0) == "3 invites sent. You'll get a notification as people reply. 1 was already on the list.")
    }

    @Test func aNewEventStartsTomorrowEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = EventTimes.parse("2026-11-02T15:00:00Z")!
        let start = EventTimes.suggestedStart(now: now, calendar: calendar)
        #expect(EventTimes.string(start) == "2026-11-04T00:00:00.000Z") // Nov 3, 7 PM EST
    }

    @Test func locationBody() {
        let body = EventLocation(name: "Park", address: "", lat: 1, lng: 2).requestBody
        #expect(body["lat"] as? Double == 1)
        #expect(EventLocation(name: "Park").requestBody["lat"] == nil)
    }
}

import Foundation
import Testing
@testable import FavWidgetsCore

struct RecentContactsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }
    private func contact(_ name: String, _ at: String) -> RecentContact {
        RecentContact(id: name, name: name, addedAt: date(at))
    }
    // Thu 2026-10-08 4 PM EDT
    private var now: Date { date("2026-10-08T20:00:00Z") }

    @Test func newestFirstCappedAtFifty() {
        let many = (0..<80).map { i in RecentContact(id: "\(i)", name: "P\(i)", addedAt: Date(timeIntervalSince1970: TimeInterval(i * 100))) }
        let latest = RecentContacts.latest(many)
        #expect(latest.count == 50)
        #expect(latest.first?.id == "79")
        #expect(latest.last?.id == "30")
    }

    @Test func sameMomentSortsByName() {
        let latest = RecentContacts.latest([contact("Zoe", "2026-10-01T12:00:00Z"), contact("Amy", "2026-10-01T12:00:00Z")])
        #expect(latest.map(\.name) == ["Amy", "Zoe"])
    }

    @Test func sectionsByRecency() {
        let list = RecentContacts.latest([
            contact("Today", "2026-10-08T15:00:00Z"),
            contact("Yesterday", "2026-10-07T15:00:00Z"),
            contact("Monday", "2026-10-05T15:00:00Z"),
            contact("August", "2026-08-03T15:00:00Z"),
            contact("Old", "2024-03-03T15:00:00Z")
        ])
        let titles = RecentContacts.sections(list, now: now, calendar: calendar).map(\.title)
        #expect(titles == ["Today", "Yesterday", "This week", "August", "March 2024"])
        // Earlier this month but more than a week ago
        let later = date("2026-10-20T20:00:00Z")
        #expect(RecentContacts.sections([contact("EarlyOct", "2026-10-02T15:00:00Z")], now: later, calendar: calendar).map(\.title) == ["This month"])
    }

    @Test func addedWording() {
        #expect(RecentContacts.addedText(date("2026-10-08T19:14:00Z"), now: now, calendar: calendar) == "Added 3:14 PM")
        #expect(RecentContacts.addedText(date("2026-10-07T19:14:00Z"), now: now, calendar: calendar) == "Added yesterday")
        #expect(RecentContacts.addedText(date("2026-10-05T19:14:00Z"), now: now, calendar: calendar) == "Added Monday")
        #expect(RecentContacts.addedText(date("2026-09-03T19:14:00Z"), now: now, calendar: calendar) == "Added Sep 3")
        #expect(RecentContacts.addedText(date("2024-03-03T19:14:00Z"), now: now, calendar: calendar) == "Added Mar 3, 2024")
    }

    @Test func importsAreSpotted() {
        let batch = (0..<12).map { RecentContact(id: "b\($0)", name: "B\($0)", addedAt: date("2025-01-01T10:00:00Z")) }
        let met = contact("Met", "2026-10-08T15:00:00Z")
        let minutes = RecentContacts.importedMinutes(batch + [met])
        #expect(RecentContacts.isImported(batch[0], in: minutes))
        #expect(!RecentContacts.isImported(met, in: minutes))
    }

    @Test func cardSummary() {
        #expect(RecentContacts.cardSummary([], now: now, calendar: calendar) == "No contacts yet")
        #expect(RecentContacts.cardSummary([contact("Jane Doe", "2026-10-08T15:00:00Z")], now: now, calendar: calendar) == "Added today: Jane Doe")
        let two = RecentContacts.latest([contact("Jane Doe", "2026-10-08T15:00:00Z"), contact("Sam", "2026-10-06T15:00:00Z")])
        #expect(RecentContacts.cardSummary(two, now: now, calendar: calendar) == "2 new this week · latest Jane Doe")
        #expect(RecentContacts.cardSummary([contact("Old Pal", "2026-09-03T15:00:00Z")], now: now, calendar: calendar) == "Latest: Old Pal · Sep 3")
    }

    @Test func namesAndPhones() {
        #expect(RecentContacts.displayName(first: "Jane", last: "Doe", organization: nil, phone: nil, email: nil) == "Jane Doe")
        #expect(RecentContacts.displayName(first: nil, last: " ", organization: "Acme Plumbing", phone: nil, email: nil) == "Acme Plumbing")
        #expect(RecentContacts.displayName(first: nil, last: nil, organization: nil, phone: "704-555-0100", email: nil) == "704-555-0100")
        #expect(RecentContacts.displayName(first: nil, last: nil, organization: nil, phone: nil, email: nil) == "No name")
        #expect(RecentContacts.dialable("+1 (704) 555-0100") == "+17045550100")
        #expect(RecentContact(id: "x", name: "Jane Q Doe", addedAt: now).initials == "JQ")
    }
}

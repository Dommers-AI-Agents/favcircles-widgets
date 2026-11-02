import Foundation

// Email invites and RSVPs for events (Wes, 2026-11-02: "similar to the
// functionality of evite.com"). The server (/api/widgets/events/:id/guests,
// /rsvp) keeps the replies; these are its shapes and the words around them.

/// Where the event is: a name and/or address, a spot when it came from a search.
public struct EventLocation: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let address: String
    public let lat: Double?
    public let lng: Double?

    public init(name: String, address: String = "", lat: Double? = nil, lng: Double? = nil) {
        self.name = name; self.address = address; self.lat = lat; self.lng = lng
    }

    public var coordinate: WidgetCoordinate? {
        guard let lat, let lng else { return nil }
        return WidgetCoordinate(latitude: lat, longitude: lng)
    }

    /// What the server stores (`location` in a create/update body)
    public var requestBody: [String: Any] {
        var body: [String: Any] = ["name": name, "address": address]
        if let lat, let lng { body["lat"] = lat; body["lng"] = lng }
        return body
    }
}

/// Going / Maybe / Can't go, or not answered yet.
public enum EventRsvp: String, Codable, CaseIterable, Sendable {
    case yes, maybe, no, pending

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventRsvp(rawValue: raw) ?? .pending
    }

    /// The three a person can pick
    public static let choices: [EventRsvp] = [.yes, .maybe, .no]

    public var label: String {
        switch self {
        case .yes: return "Going"
        case .maybe: return "Maybe"
        case .no: return "Can't go"
        case .pending: return "No reply"
        }
    }

    public var emoji: String {
        switch self {
        case .yes: return "🎉"
        case .maybe: return "🤔"
        case .no: return "😢"
        case .pending: return "✉️"
        }
    }
}

/// The viewer's own reply (members; joining counts as Going).
public struct EventMyRsvp: Decodable, Equatable, Hashable, Sendable {
    public let rsvp: EventRsvp
    public let adults: Int
    public let kids: Int
    public let note: String?

    public init(rsvp: EventRsvp, adults: Int = 1, kids: Int = 0, note: String? = nil) {
        self.rsvp = rsvp; self.adults = adults; self.kids = kids; self.note = note
    }
}

/// Replies and heads per answer.
public struct EventRsvpCounts: Decodable, Equatable, Hashable, Sendable {
    public struct Bucket: Decodable, Equatable, Hashable, Sendable {
        public let replies: Int
        public let people: Int
        public init(replies: Int, people: Int) { self.replies = replies; self.people = people }
    }
    public let yes: Bucket
    public let maybe: Bucket
    public let no: Bucket
    public let pending: Bucket

    public init(yes: Bucket, maybe: Bucket, no: Bucket, pending: Bucket) {
        self.yes = yes; self.maybe = maybe; self.no = no; self.pending = pending
    }

    public func bucket(_ rsvp: EventRsvp) -> Bucket {
        switch rsvp {
        case .yes: return yes
        case .maybe: return maybe
        case .no: return no
        case .pending: return pending
        }
    }
}

/// One person on the guest list: a member, an in-app invitee or an email guest.
/// `email`, `note` and the email bookkeeping are the coordinator's only.
public struct EventGuest: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    /// "member" | "invited" | "email"
    public let kind: String
    public let name: String
    public let rsvp: EventRsvp
    public let adults: Int?
    public let kids: Int?
    public let note: String?
    public let email: String?
    public let avatarUrl: String?
    public let isHost: Bool?
    public let optedOut: Bool?
    public let joinedInApp: Bool?
    public let lastEmailedAt: String?

    public init(id: String, kind: String, name: String, rsvp: EventRsvp, adults: Int? = nil, kids: Int? = nil, note: String? = nil,
                email: String? = nil, avatarUrl: String? = nil, isHost: Bool? = nil, optedOut: Bool? = nil,
                joinedInApp: Bool? = nil, lastEmailedAt: String? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.rsvp = rsvp; self.adults = adults; self.kids = kids
        self.note = note; self.email = email; self.avatarUrl = avatarUrl; self.isHost = isHost; self.optedOut = optedOut
        self.joinedInApp = joinedInApp; self.lastEmailedAt = lastEmailedAt
    }

    public var isEmailGuest: Bool { kind == "email" }
    /// Who to show: their name, or the address when the coordinator didn't give one
    public var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return email ?? "Guest"
    }
}

/// GET /widgets/events/:id/guests
public struct EventGuestList: Decodable, Equatable, Sendable {
    public let guests: [EventGuest]
    public let counts: EventRsvpCounts
    /// Coordinator only
    public let emailsLeftToday: Int?
    public let maxGuests: Int?

    public init(guests: [EventGuest], counts: EventRsvpCounts, emailsLeftToday: Int? = nil, maxGuests: Int? = nil) {
        self.guests = guests; self.counts = counts; self.emailsLeftToday = emailsLeftToday; self.maxGuests = maxGuests
    }
}

/// ISO times to and from the server (one helper for every Events screen).
public enum EventTimes {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    /// Server timestamps, with or without fractional seconds
    public static func parse(_ iso: String) -> Date? { withFraction.date(from: iso) ?? plain.date(from: iso) }
    public static func date(_ iso: String) -> Date? { parse(iso) }
    public static func string(_ date: Date) -> String { withFraction.string(from: date) }

    /// A sensible first start for a new event: the next whole hour, at least
    /// a day out, at 7 PM. Pure (the calendar and now are passed in).
    public static func suggestedStart(now: Date, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// The words around invites and replies. Pure, tested on the Mac.
public enum EventRsvpCopy {
    /// "12 going · 3 maybe · 5 no reply" (people, not replies; zeros left out)
    public static func summary(_ counts: EventRsvpCounts?) -> String? {
        guard let counts else { return nil }
        var parts: [String] = []
        if counts.yes.people > 0 { parts.append("\(counts.yes.people) going") }
        if counts.maybe.people > 0 { parts.append("\(counts.maybe.people) maybe") }
        if counts.no.replies > 0 { parts.append("\(counts.no.replies) can't go") }
        if counts.pending.replies > 0 { parts.append("\(counts.pending.replies) no reply") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "+2" for a party of three; empty for one
    public static func partySize(adults: Int?, kids: Int?) -> String {
        let total = max(1, (adults ?? 1) + (kids ?? 0))
        guard total > 1 else { return "" }
        var bits: [String] = []
        if let adults, adults > 0 { bits.append("\(adults) adult\(adults == 1 ? "" : "s")") }
        if let kids, kids > 0 { bits.append("\(kids) kid\(kids == 1 ? "" : "s")") }
        return bits.joined(separator: ", ")
    }

    /// The addresses in whatever was pasted or typed: commas, semicolons,
    /// spaces, new lines, "Name <a@b.com>". Lower-cased, de-duplicated, in
    /// order; anything that isn't an address comes back in `invalid`.
    public static func parseEmails(_ text: String) -> (emails: [String], invalid: [String]) {
        var emails: [String] = []
        var invalid: [String] = []
        var seen = Set<String>()
        let separators = CharacterSet(charactersIn: ",;\n\r\t ")
        for raw in text.components(separatedBy: separators) {
            var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>()\"'"))
            guard !token.isEmpty else { continue }
            guard token.contains("@") else { continue } // names around an address
            let email = token.lowercased()
            if isEmail(email) {
                if seen.insert(email).inserted { emails.append(email) }
            } else {
                invalid.append(token)
            }
        }
        return (emails, invalid)
    }

    public static func isEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, text.count <= 254 else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        let tld = domain[domain.index(after: dot)...]
        let bad = CharacterSet(charactersIn: " <>(),;:\"")
        return tld.count >= 2 && tld.allSatisfy(\.isLetter) && text.rangeOfCharacter(from: bad) == nil
    }

    public static func inviteEmailsButton(_ count: Int) -> String {
        count == 0 ? "Send invites" : "Send \(count) invite\(count == 1 ? "" : "s")"
    }

    /// The result after sending
    public static func invitesSent(sent: Int, already: Int, invalid: Int) -> String {
        var lines = ["\(sent) invite\(sent == 1 ? "" : "s") sent. You'll get a notification as people reply."]
        if already > 0 { lines.append("\(already) \(already == 1 ? "was" : "were") already on the list.") }
        if invalid > 0 { lines.append("\(invalid) \(invalid == 1 ? "address doesn't" : "addresses don't") look right.") }
        return lines.joined(separator: " ")
    }

    /// The member's own reply line: "You're going (2 adults, 1 kid)"
    public static func myReply(_ mine: EventMyRsvp?) -> String? {
        guard let mine else { return nil }
        let party = partySize(adults: mine.adults, kids: mine.kids)
        let suffix = party.isEmpty ? "" : " (\(party))"
        switch mine.rsvp {
        case .yes: return "You're going\(suffix)"
        case .maybe: return "You might go\(suffix)"
        case .no: return "You can't make it"
        case .pending: return nil
        }
    }

    /// Who a guest message goes to
    public enum Audience: String, CaseIterable, Sendable {
        case all, going, yes, maybe, pending
        public var label: String {
            switch self {
            case .all: return "Everyone who hasn't said no"
            case .going: return "Going and maybe"
            case .yes: return "Going"
            case .maybe: return "Maybe"
            case .pending: return "No reply yet"
            }
        }
    }
}

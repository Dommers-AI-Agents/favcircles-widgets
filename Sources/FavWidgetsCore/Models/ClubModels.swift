import Foundation

// Clubs (Wes, 2026-10-21: "a new widget that revolves around clubs. Think a
// run club. People, event, days times, bulletin board or message board.
// Maybe both."), as the server describes them (`/api/widgets/clubs`).
// Membership, posts and RSVPs are members-only server-side.

/// What kind of club it is: the emoji it starts with and how it's named.
public enum ClubKind: String, Codable, CaseIterable, Sendable {
    case run, walk, ride, hike, swim, yoga, book, other

    public var emoji: String {
        switch self {
        case .run: return "🏃"
        case .walk: return "🚶"
        case .ride: return "🚴"
        case .hike: return "🥾"
        case .swim: return "🏊"
        case .yoga: return "🧘"
        case .book: return "📚"
        case .other: return "🤝"
        }
    }

    public var label: String {
        switch self {
        case .run: return "Run club"
        case .walk: return "Walking club"
        case .ride: return "Ride club"
        case .hike: return "Hiking club"
        case .swim: return "Swim club"
        case .yoga: return "Yoga club"
        case .book: return "Book club"
        case .other: return "Club"
        }
    }

    /// An unknown kind from a newer server reads as "other".
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClubKind(rawValue: raw) ?? .other
    }
}

public enum ClubRole: String, Codable, Sendable {
    case owner, organizer, member

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClubRole(rawValue: raw) ?? .member
    }

    /// Organizers (and the owner) run the schedule, the bulletin and the people.
    public var canOrganize: Bool { self != .member }

    public var label: String {
        switch self {
        case .owner: return "Owner"
        case .organizer: return "Organizer"
        case .member: return "Member"
        }
    }
}

/// Where a club meets.
public struct ClubSpot: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var address: String?
    public var lat: Double?
    public var lng: Double?

    public init(name: String, address: String? = nil, lat: Double? = nil, lng: Double? = nil) {
        self.name = name
        self.address = address
        self.lat = lat
        self.lng = lng
    }

    /// The JSON body field (nil = no spot).
    public var body: [String: Any] {
        var out: [String: Any] = ["name": name]
        if let address, !address.isEmpty { out["address"] = address }
        if let lat { out["lat"] = lat }
        if let lng { out["lng"] = lng }
        return out
    }
}

/// A weekly meetup: "Saturday long run, 7 AM at Freedom Park".
public struct ClubMeetup: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    /// 0 = Sunday … 6 = Saturday
    public let weekday: Int
    /// "HH:mm", 24-hour, in the club's time zone
    public let time: String
    public let title: String
    public let spot: ClubSpot?
    public let notes: String?

    public init(id: String, weekday: Int, time: String, title: String, spot: ClubSpot? = nil, notes: String? = nil) {
        self.id = id; self.weekday = weekday; self.time = time; self.title = title; self.spot = spot; self.notes = notes
    }
}

/// A one-off event (a race day, a social).
public struct ClubEvent: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date
    public let spot: ClubSpot?
    public let notes: String?

    public init(id: String, title: String, startsAt: Date, spot: ClubSpot? = nil, notes: String? = nil) {
        self.id = id; self.title = title; self.startsAt = startsAt; self.spot = spot; self.notes = notes
    }
}

public struct ClubPerson: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let userId: String
    public let name: String
    public let avatarUrl: String?
    public var id: String { userId }

    public init(userId: String, name: String, avatarUrl: String? = nil) {
        self.userId = userId; self.name = name; self.avatarUrl = avatarUrl
    }
}

public struct ClubMember: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let userId: String
    public let name: String
    public let avatarUrl: String?
    public let role: ClubRole
    public let joinedAt: Date?
    public var id: String { userId }

    public init(userId: String, name: String, avatarUrl: String? = nil, role: ClubRole, joinedAt: Date? = nil) {
        self.userId = userId; self.name = name; self.avatarUrl = avatarUrl; self.role = role; self.joinedAt = joinedAt
    }
}

public enum ClubRSVP: String, Codable, Sendable {
    case going, not
}

/// One dated meetup or event, with who's going.
public struct ClubOccurrence: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// `m_<meetupId>_<YYYY-MM-DD>` or `e_<eventId>`
    public let key: String
    /// "meetup" | "event"
    public let kind: String
    public let title: String
    public let startsAt: Date
    public let spot: ClubSpot?
    public let notes: String?
    public let going: [ClubPerson]
    public let notGoingCount: Int
    public let myRsvp: ClubRSVP?
    public var id: String { key }

    public init(key: String, kind: String, title: String, startsAt: Date, spot: ClubSpot? = nil, notes: String? = nil,
                going: [ClubPerson] = [], notGoingCount: Int = 0, myRsvp: ClubRSVP? = nil) {
        self.key = key; self.kind = kind; self.title = title; self.startsAt = startsAt; self.spot = spot; self.notes = notes
        self.going = going; self.notGoingCount = notGoingCount; self.myRsvp = myRsvp
    }

    enum CodingKeys: String, CodingKey { case key, kind, title, startsAt, spot, notes, going, notGoingCount, myRsvp }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "meetup"
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        startsAt = try c.decode(Date.self, forKey: .startsAt)
        spot = try? c.decodeIfPresent(ClubSpot.self, forKey: .spot)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        going = (try? c.decodeIfPresent([ClubPerson].self, forKey: .going)) ?? []
        notGoingCount = (try? c.decodeIfPresent(Int.self, forKey: .notGoingCount)) ?? 0
        myRsvp = try? c.decodeIfPresent(ClubRSVP.self, forKey: .myRsvp)
    }

    public var isEvent: Bool { kind == "event" }

    /// The same occurrence with my answer changed (optimistic RSVP).
    public func with(myRsvp rsvp: ClubRSVP?, me: ClubPerson?) -> ClubOccurrence {
        var people = going.filter { $0.userId != me?.userId }
        if rsvp == .going, let me { people.insert(me, at: 0) }
        var notCount = notGoingCount - (myRsvp == .not ? 1 : 0)
        if rsvp == .not { notCount += 1 }
        return ClubOccurrence(key: key, kind: kind, title: title, startsAt: startsAt, spot: spot, notes: notes,
                              going: people, notGoingCount: max(0, notCount), myRsvp: rsvp)
    }
}

/// A bulletin announcement or a board post.
public struct ClubPost: Codable, Identifiable, Equatable, Hashable, Sendable {
    public struct Reaction: Codable, Equatable, Hashable, Sendable {
        public let emoji: String
        public let count: Int
        public let mine: Bool
        public init(emoji: String, count: Int, mine: Bool) { self.emoji = emoji; self.count = count; self.mine = mine }
    }

    public let id: String
    /// "bulletin" | "board"
    public let kind: String
    public let authorId: String
    public let authorName: String
    public let authorAvatar: String?
    public let text: String
    public let photoUrl: String?
    public let createdAt: Date?
    public let replyCount: Int
    public let reactions: [Reaction]
    public let canDelete: Bool

    public init(id: String, kind: String, authorId: String, authorName: String, authorAvatar: String? = nil, text: String,
                photoUrl: String? = nil, createdAt: Date? = nil, replyCount: Int = 0, reactions: [Reaction] = [], canDelete: Bool = false) {
        self.id = id; self.kind = kind; self.authorId = authorId; self.authorName = authorName; self.authorAvatar = authorAvatar
        self.text = text; self.photoUrl = photoUrl; self.createdAt = createdAt; self.replyCount = replyCount
        self.reactions = reactions; self.canDelete = canDelete
    }

    enum CodingKeys: String, CodingKey { case id, kind, authorId, authorName, authorAvatar, text, photoUrl, createdAt, replyCount, reactions, canDelete }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "board"
        authorId = (try? c.decode(String.self, forKey: .authorId)) ?? ""
        authorName = (try? c.decode(String.self, forKey: .authorName)) ?? "Someone"
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        replyCount = (try? c.decodeIfPresent(Int.self, forKey: .replyCount)) ?? 0
        reactions = (try? c.decodeIfPresent([Reaction].self, forKey: .reactions)) ?? []
        canDelete = (try? c.decodeIfPresent(Bool.self, forKey: .canDelete)) ?? false
    }

    public var isBulletin: Bool { kind == "bulletin" }
    public var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }
    public var myReaction: String? { reactions.first(where: \.mine)?.emoji }
}

public struct ClubReply: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let authorId: String
    public let authorName: String
    public let authorAvatar: String?
    public let text: String
    public let createdAt: Date?
    public let canDelete: Bool

    public init(id: String, authorId: String, authorName: String, authorAvatar: String? = nil, text: String,
                createdAt: Date? = nil, canDelete: Bool = false) {
        self.id = id; self.authorId = authorId; self.authorName = authorName; self.authorAvatar = authorAvatar
        self.text = text; self.createdAt = createdAt; self.canDelete = canDelete
    }
}

/// A club in "my clubs".
public struct ClubSummary: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let kind: ClubKind
    public let memberCount: Int
    public let myRole: ClubRole
    public let muted: Bool
    public let next: ClubOccurrence?

    public init(id: String, name: String, emoji: String, kind: ClubKind, memberCount: Int, myRole: ClubRole,
                muted: Bool = false, next: ClubOccurrence? = nil) {
        self.id = id; self.name = name; self.emoji = emoji; self.kind = kind; self.memberCount = memberCount
        self.myRole = myRole; self.muted = muted; self.next = next
    }

    enum CodingKeys: String, CodingKey { case id, name, emoji, kind, memberCount, myRole, muted, next }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Club"
        kind = (try? c.decode(ClubKind.self, forKey: .kind)) ?? .other
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? kind.emoji
        memberCount = (try? c.decode(Int.self, forKey: .memberCount)) ?? 0
        myRole = (try? c.decode(ClubRole.self, forKey: .myRole)) ?? .member
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        next = try? c.decodeIfPresent(ClubOccurrence.self, forKey: .next)
    }
}

/// Everything about one club, for its page.
public struct Club: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let kind: ClubKind
    public let memberCount: Int
    public let myRole: ClubRole
    public let muted: Bool
    public let next: ClubOccurrence?
    public let description: String
    public let homeSpot: ClubSpot?
    public let timezone: String?
    public let ownerId: String
    public let ownerName: String
    public let joinOpen: Bool
    public let inviteLink: String?
    public let scheduleLine: String?
    public let schedule: [ClubMeetup]
    public let events: [ClubEvent]
    public let members: [ClubMember]
    public let upcoming: [ClubOccurrence]
    public let bulletin: [ClubPost]
    public let boardPreview: [ClubPost]

    public init(id: String, name: String, emoji: String, kind: ClubKind, memberCount: Int, myRole: ClubRole, muted: Bool = false,
                next: ClubOccurrence? = nil, description: String = "", homeSpot: ClubSpot? = nil, timezone: String? = nil,
                ownerId: String = "", ownerName: String = "", joinOpen: Bool = true, inviteLink: String? = nil,
                scheduleLine: String? = nil, schedule: [ClubMeetup] = [], events: [ClubEvent] = [], members: [ClubMember] = [],
                upcoming: [ClubOccurrence] = [], bulletin: [ClubPost] = [], boardPreview: [ClubPost] = []) {
        self.id = id; self.name = name; self.emoji = emoji; self.kind = kind; self.memberCount = memberCount
        self.myRole = myRole; self.muted = muted; self.next = next; self.description = description; self.homeSpot = homeSpot
        self.timezone = timezone; self.ownerId = ownerId; self.ownerName = ownerName; self.joinOpen = joinOpen
        self.inviteLink = inviteLink; self.scheduleLine = scheduleLine; self.schedule = schedule; self.events = events
        self.members = members; self.upcoming = upcoming; self.bulletin = bulletin; self.boardPreview = boardPreview
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, kind, memberCount, myRole, muted, next, description, homeSpot, timezone, ownerId, ownerName
        case joinOpen, inviteLink, scheduleLine, schedule, events, members, upcoming, bulletin, boardPreview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Club"
        kind = (try? c.decode(ClubKind.self, forKey: .kind)) ?? .other
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? kind.emoji
        memberCount = (try? c.decode(Int.self, forKey: .memberCount)) ?? 0
        myRole = (try? c.decode(ClubRole.self, forKey: .myRole)) ?? .member
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        next = try? c.decodeIfPresent(ClubOccurrence.self, forKey: .next)
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        homeSpot = try? c.decodeIfPresent(ClubSpot.self, forKey: .homeSpot)
        timezone = try? c.decodeIfPresent(String.self, forKey: .timezone)
        ownerId = (try? c.decodeIfPresent(String.self, forKey: .ownerId)) ?? ""
        ownerName = (try? c.decodeIfPresent(String.self, forKey: .ownerName)) ?? ""
        joinOpen = (try? c.decodeIfPresent(Bool.self, forKey: .joinOpen)) ?? true
        inviteLink = try? c.decodeIfPresent(String.self, forKey: .inviteLink)
        scheduleLine = try? c.decodeIfPresent(String.self, forKey: .scheduleLine)
        schedule = (try? c.decodeIfPresent([ClubMeetup].self, forKey: .schedule)) ?? []
        events = (try? c.decodeIfPresent([ClubEvent].self, forKey: .events)) ?? []
        members = (try? c.decodeIfPresent([ClubMember].self, forKey: .members)) ?? []
        upcoming = (try? c.decodeIfPresent([ClubOccurrence].self, forKey: .upcoming)) ?? []
        bulletin = (try? c.decodeIfPresent([ClubPost].self, forKey: .bulletin)) ?? []
        boardPreview = (try? c.decodeIfPresent([ClubPost].self, forKey: .boardPreview)) ?? []
    }

    public var inviteURL: URL? { inviteLink.flatMap(URL.init(string:)) }
    public var timeZone: TimeZone { timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
    public var canOrganize: Bool { myRole.canOrganize }
    public var isOwner: Bool { myRole == .owner }

    public var summary: ClubSummary {
        ClubSummary(id: id, name: name, emoji: emoji, kind: kind, memberCount: memberCount, myRole: myRole, muted: muted,
                    next: upcoming.first ?? next)
    }

    /// The page with one occurrence replaced (after an RSVP).
    public func replacing(_ occurrence: ClubOccurrence) -> Club {
        let swap: (ClubOccurrence) -> ClubOccurrence = { $0.key == occurrence.key ? occurrence : $0 }
        return Club(id: id, name: name, emoji: emoji, kind: kind, memberCount: memberCount, myRole: myRole, muted: muted,
                    next: next.map(swap), description: description, homeSpot: homeSpot, timezone: timezone, ownerId: ownerId,
                    ownerName: ownerName, joinOpen: joinOpen, inviteLink: inviteLink, scheduleLine: scheduleLine,
                    schedule: schedule, events: events, members: members, upcoming: upcoming.map(swap),
                    bulletin: bulletin, boardPreview: boardPreview)
    }
}

/// What a link shows before you join.
public struct ClubInvitePreview: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let kind: ClubKind
    public let description: String
    public let ownerName: String
    public let memberCount: Int
    public let joinOpen: Bool
    public let alreadyMember: Bool
    public let scheduleLine: String?

    public init(id: String, name: String, emoji: String, kind: ClubKind, description: String = "", ownerName: String,
                memberCount: Int, joinOpen: Bool = true, alreadyMember: Bool = false, scheduleLine: String? = nil) {
        self.id = id; self.name = name; self.emoji = emoji; self.kind = kind; self.description = description
        self.ownerName = ownerName; self.memberCount = memberCount; self.joinOpen = joinOpen
        self.alreadyMember = alreadyMember; self.scheduleLine = scheduleLine
    }

    enum CodingKeys: String, CodingKey { case id, name, emoji, kind, description, ownerName, memberCount, joinOpen, alreadyMember, scheduleLine }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Club"
        kind = (try? c.decode(ClubKind.self, forKey: .kind)) ?? .other
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? kind.emoji
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        ownerName = (try? c.decodeIfPresent(String.self, forKey: .ownerName)) ?? "Someone"
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        joinOpen = (try? c.decodeIfPresent(Bool.self, forKey: .joinOpen)) ?? true
        alreadyMember = (try? c.decodeIfPresent(Bool.self, forKey: .alreadyMember)) ?? false
        scheduleLine = try? c.decodeIfPresent(String.self, forKey: .scheduleLine)
    }
}

// MARK: - Copy

/// The words the Clubs screens use. Pure, so they're tested on a Mac.
public enum ClubCopy {
    /// Sunday-first, matching the server's weekday numbers.
    public static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func weekdayName(_ weekday: Int) -> String {
        weekdayNames.indices.contains(weekday) ? weekdayNames[weekday] : "Day"
    }

    /// "Saturdays"
    public static func weekdayPlural(_ weekday: Int) -> String { weekdayName(weekday) + "s" }

    /// "07:00" → "7 AM", "18:30" → "6:30 PM"
    public static func clock(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return hhmm }
        let h = parts[0], m = parts[1]
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12)\(m == 0 ? "" : String(format: ":%02d", m)) \(h < 12 ? "AM" : "PM")"
    }

    /// A Date's clock time: "7 AM", "6:30 PM"
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return clock(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
    }

    /// "Saturdays 7 AM"
    public static func meetupLine(_ meetup: ClubMeetup) -> String {
        "\(weekdayPlural(meetup.weekday)) \(clock(meetup.time))"
    }

    /// "Saturdays 7 AM · Wednesdays 6:30 PM" — the server's line when it sent one.
    public static func scheduleLine(_ schedule: [ClubMeetup], server: String? = nil) -> String? {
        if let server, !server.isEmpty { return server }
        guard !schedule.isEmpty else { return nil }
        return schedule.sorted { ($0.weekday, $0.time) < ($1.weekday, $1.time) }.map(meetupLine).joined(separator: " · ")
    }

    /// "Sat, Oct 25 · 7 AM"
    public static func occurrenceLine(_ date: Date, timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = "EEE, MMM d"
        return "\(f.string(from: date)) · \(clock(date, timeZone: timeZone))"
    }

    /// "Today 7 AM", "Tomorrow 6:30 PM", "Sat 7 AM" this week, else the full line.
    public static func relative(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 99
        let time = clock(date, timeZone: timeZone)
        switch days {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case 2...6:
            let weekday = cal.component(.weekday, from: date) - 1
            return "\(weekdayShort[weekday]) \(time)"
        default: return occurrenceLine(date, timeZone: timeZone)
        }
    }

    /// "Ana, Joe and 4 others going" / "Ana going" / "You and Ana going" / "Nobody's said yet"
    public static func goingLine(_ going: [ClubPerson], meId: String? = nil) -> String {
        guard !going.isEmpty else { return "Nobody's said yet" }
        var names = going.map { $0.userId == meId ? "You" : firstName($0.name) }
        if let i = names.firstIndex(of: "You"), i != 0 { names.remove(at: i); names.insert("You", at: 0) }
        switch names.count {
        case 1: return "\(names[0]) going"
        case 2: return "\(names[0]) and \(names[1]) going"
        case 3: return "\(names[0]), \(names[1]) and \(names[2]) going"
        default:
            let others = names.count - 2
            return "\(names[0]), \(names[1]) and \(others) others going"
        }
    }

    public static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// "1 member", "12 members"
    public static func memberCount(_ n: Int) -> String { n == 1 ? "1 member" : "\(n) members" }

    /// "6 going"
    public static func goingCount(_ n: Int) -> String { "\(n) going" }

    /// "3 replies" / "Reply"
    public static func replies(_ n: Int) -> String {
        switch n {
        case 0: return "Reply"
        case 1: return "1 reply"
        default: return "\(n) replies"
        }
    }

    /// Where an occurrence meets: the spot's name.
    public static func spotLine(_ spot: ClubSpot?) -> String? {
        guard let spot, !spot.name.isEmpty else { return nil }
        return spot.name
    }

    /// The card's line: "Sat 7 AM · Charlotte Run Club · 6 going"
    public static func cardLine(club: String, next: ClubOccurrence, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var parts = [relative(next.startsAt, now: now, timeZone: timeZone), club]
        if !next.going.isEmpty { parts.append(goingCount(next.going.count)) }
        return parts.joined(separator: " · ")
    }

    /// The soonest upcoming occurrence across clubs, for the card.
    public static func soonest(_ clubs: [ClubSummary], now: Date = Date()) -> (club: ClubSummary, next: ClubOccurrence)? {
        clubs.compactMap { club in club.next.map { (club, $0) } }
            .filter { $0.1.startsAt > now.addingTimeInterval(-3600) }
            .min { $0.1.startsAt < $1.1.startsAt }
    }

    /// The join screen's button.
    public static func joinButton(_ preview: ClubInvitePreview) -> String { "Join \(preview.name)" }

    /// Pulls the invite token out of a pasted link or a bare token.
    public static func token(fromPasted text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: String
        if trimmed.hasPrefix("circles://club/") {
            candidate = String(trimmed.dropFirst("circles://club/".count))
        } else if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            let parts = url.path.split(separator: "/").map(String.init)
            guard let i = parts.firstIndex(of: "club"), parts.indices.contains(i + 1) else { return nil }
            candidate = parts[i + 1]
        } else {
            candidate = trimmed
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard (16...32).contains(candidate.count), candidate.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return candidate
    }

    /// One reaction set offered on posts.
    public static let reactionChoices = ["👍", "❤️", "🔥", "😂", "👏", "🏃"]

    /// The time a reminder fires: one hour before.
    public static func reminderDate(for occurrence: ClubOccurrence) -> Date {
        occurrence.startsAt.addingTimeInterval(-3600)
    }

    /// Whether a reminder at `date` would land in quiet hours (minutes of
    /// the day in the device's zone), in which case it isn't scheduled.
    public static func reminderIsQuiet(_ date: Date, quietHours: WidgetQuietHours?, calendar: Calendar = .current) -> Bool {
        guard let quietHours else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return quietHours.contains(minute: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

import SwiftUI
import FavWidgetsCore

/// Talks to `/api/widgets/clubs` through the host's API channel.
struct ClubsClient {
    let context: WidgetContext

    private struct ListResponse: Decodable { let clubs: [ClubSummary] }
    private struct ClubResponse: Decodable { let club: Club }
    private struct PreviewResponse: Decodable { let preview: ClubInvitePreview }
    struct JoinResponse: Decodable { let club: Club; let joined: Bool }
    private struct OccurrenceResponse: Decodable { let occurrence: ClubOccurrence }
    struct PostsPage: Decodable { let posts: [ClubPost]; let hasMore: Bool? }
    private struct PostResponse: Decodable { let post: ClubPost }
    private struct RepliesResponse: Decodable { let replies: [ClubReply] }
    struct ReplyResponse: Decodable { let reply: ClubReply; let post: ClubPost? }
    private struct InviteResponse: Decodable { let invited: Int }

    func list() async throws -> [ClubSummary] {
        let r: ListResponse = try await context.api(.get, "widgets/clubs"); return r.clubs
    }
    func create(name: String, kind: ClubKind, emoji: String, description: String, homeSpot: ClubSpot?) async throws -> Club {
        var body: [String: Any] = ["name": name, "kind": kind.rawValue, "emoji": emoji, "description": description,
                                   "timezone": TimeZone.current.identifier]
        if let homeSpot { body["homeSpot"] = homeSpot.body }
        let r: ClubResponse = try await context.api(.post, "widgets/clubs", body: body); return r.club
    }
    func detail(_ id: String) async throws -> Club {
        let r: ClubResponse = try await context.api(.get, "widgets/clubs/\(id)"); return r.club
    }
    func preview(token: String) async throws -> ClubInvitePreview {
        let r: PreviewResponse = try await context.api(.get, "widgets/clubs/invite/\(token)"); return r.preview
    }
    func join(token: String) async throws -> JoinResponse {
        try await context.api(.post, "widgets/clubs/join", body: ["token": token])
    }
    /// Edit: name, emoji, kind, description, homeSpot (NSNull clears), joinOpen.
    func update(_ id: String, _ body: [String: Any]) async throws -> Club {
        let r: ClubResponse = try await context.api(.put, "widgets/clubs/\(id)", body: body); return r.club
    }
    func end(_ id: String) async throws { _ = try await context.apiData(.delete, "widgets/clubs/\(id)") }
    func leave(_ id: String) async throws { _ = try await context.apiData(.post, "widgets/clubs/\(id)/leave") }
    func mute(_ id: String, _ muted: Bool) async throws -> Club {
        let r: ClubResponse = try await context.api(.post, "widgets/clubs/\(id)/mute", body: ["muted": muted]); return r.club
    }
    func remove(_ id: String, member: String) async throws -> Club {
        let r: ClubResponse = try await context.api(.delete, "widgets/clubs/\(id)/members/\(member)"); return r.club
    }
    func setRole(_ id: String, member: String, role: ClubRole) async throws -> Club {
        let r: ClubResponse = try await context.api(.post, "widgets/clubs/\(id)/members/\(member)/role", body: ["role": role.rawValue])
        return r.club
    }
    func resetLink(_ id: String) async throws -> Club {
        let r: ClubResponse = try await context.api(.post, "widgets/clubs/\(id)/link/reset"); return r.club
    }
    func invite(_ id: String, userIds: [String]) async throws -> Int {
        let r: InviteResponse = try await context.api(.post, "widgets/clubs/\(id)/invite", body: ["userIds": userIds]); return r.invited
    }

    // MARK: Schedule

    static func meetupBody(weekday: Int, time: String, title: String, spot: ClubSpot?, notes: String) -> [String: Any] {
        var body: [String: Any] = ["weekday": weekday, "time": time, "title": title, "notes": notes]
        body["spot"] = spot?.body ?? NSNull()
        return body
    }
    func addMeetup(_ id: String, _ body: [String: Any]) async throws -> Club {
        let r: ClubResponse = try await context.api(.post, "widgets/clubs/\(id)/schedule", body: body); return r.club
    }
    func updateMeetup(_ id: String, meetup: String, _ body: [String: Any]) async throws -> Club {
        let r: ClubResponse = try await context.api(.put, "widgets/clubs/\(id)/schedule/\(meetup)", body: body); return r.club
    }
    func deleteMeetup(_ id: String, meetup: String) async throws -> Club {
        let r: ClubResponse = try await context.api(.delete, "widgets/clubs/\(id)/schedule/\(meetup)"); return r.club
    }
    func addEvent(_ id: String, title: String, startsAt: Date, spot: ClubSpot?, notes: String) async throws -> Club {
        var body: [String: Any] = ["title": title, "startsAt": ISO8601DateFormatter().string(from: startsAt), "notes": notes]
        body["spot"] = spot?.body ?? NSNull()
        let r: ClubResponse = try await context.api(.post, "widgets/clubs/\(id)/events", body: body); return r.club
    }
    func deleteEvent(_ id: String, event: String) async throws -> Club {
        let r: ClubResponse = try await context.api(.delete, "widgets/clubs/\(id)/events/\(event)"); return r.club
    }
    func rsvp(_ id: String, key: String, status: ClubRSVP?) async throws -> ClubOccurrence {
        let r: OccurrenceResponse = try await context.api(.post, "widgets/clubs/\(id)/rsvp",
                                                          body: ["key": key, "status": status?.rawValue ?? NSNull()])
        return r.occurrence
    }

    // MARK: Bulletin + board

    func posts(_ id: String, kind: String, before: Date? = nil) async throws -> PostsPage {
        var path = "widgets/clubs/\(id)/posts?kind=\(kind)"
        if let before {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            path += "&before=\(iso.string(from: before).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        }
        return try await context.api(.get, path)
    }
    func post(_ id: String, kind: String, text: String, photoUrl: URL?) async throws -> ClubPost {
        var body: [String: Any] = ["kind": kind, "text": text]
        if let photoUrl { body["photoUrl"] = photoUrl.absoluteString }
        let r: PostResponse = try await context.api(.post, "widgets/clubs/\(id)/posts", body: body); return r.post
    }
    func deletePost(_ id: String, post: String) async throws { _ = try await context.apiData(.delete, "widgets/clubs/\(id)/posts/\(post)") }
    func react(_ id: String, post: String, emoji: String?) async throws -> ClubPost {
        let r: PostResponse = try await context.api(.post, "widgets/clubs/\(id)/posts/\(post)/react", body: ["emoji": emoji ?? NSNull()])
        return r.post
    }
    func replies(_ id: String, post: String) async throws -> [ClubReply] {
        let r: RepliesResponse = try await context.api(.get, "widgets/clubs/\(id)/posts/\(post)/replies"); return r.replies
    }
    func reply(_ id: String, post: String, text: String) async throws -> ReplyResponse {
        try await context.api(.post, "widgets/clubs/\(id)/posts/\(post)/replies", body: ["text": text])
    }
    func deleteReply(_ id: String, post: String, reply: String) async throws {
        _ = try await context.apiData(.delete, "widgets/clubs/\(id)/posts/\(post)/replies/\(reply)")
    }
}

/// The user's clubs, shared by the card and the full view.
@MainActor
final class ClubsStore: RemoteStore {
    @Published private(set) var clubs: [ClubSummary] = []

    static func shared(in context: WidgetContext) -> ClubsStore {
        context.transient("clubs.store") { ClubsStore() }
    }

    func refresh(_ context: WidgetContext, force: Bool = false) async {
        let client = ClubsClient(context: context)
        if force {
            await load { self.clubs = try await client.list() }
        } else {
            await loadIfNeeded(staleAfter: 60) { self.clubs = try await client.list() }
        }
    }

    func upsert(_ club: ClubSummary) {
        if let i = clubs.firstIndex(where: { $0.id == club.id }) { clubs[i] = club } else { clubs.insert(club, at: 0) }
        markLoaded()
    }

    func remove(_ id: String) { clubs.removeAll { $0.id == id } }
}

/// One open club page: the club, kept current while on screen.
@MainActor
final class ClubDetailModel: ObservableObject {
    @Published var club: Club?
    @Published var error: String?

    let clubId: String
    let client: ClubsClient

    init(clubId: String, context: WidgetContext) {
        self.clubId = clubId
        self.client = ClubsClient(context: context)
    }

    func load() async {
        do { club = try await client.detail(clubId); error = nil } catch {
            guard !WidgetErrorText.isCancellation(error) else { return }
            self.error = (error as NSError).localizedDescription.isEmpty ? "Couldn't load the club. Pull to try again." : (error as NSError).localizedDescription
        }
    }
}

/// Local reminders an hour before what you said you're going to.
enum ClubReminders {
    static let prefix = "club-"

    /// Going → schedule (unless it lands in quiet hours or has passed);
    /// anything else → cancel.
    static func sync(_ occurrence: ClubOccurrence, clubName: String, emoji: String, quietHours: WidgetQuietHours?) async {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let id = prefix + occurrence.key
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard occurrence.myRsvp == .going else { return }
        let fireAt = ClubCopy.reminderDate(for: occurrence)
        guard fireAt > Date(), !ClubCopy.reminderIsQuiet(fireAt, quietHours: quietHours) else { return }
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(emoji) \(clubName) in an hour"
        content.body = [occurrence.title, ClubCopy.spotLine(occurrence.spot)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = "clubs"
        content.userInfo = ["type": "club_reminder"]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
        #endif
    }

    /// Leaving or ending a club: drop its pending reminders.
    static func cancel(_ occurrences: [ClubOccurrence]) {
        #if canImport(UserNotifications) && !os(macOS)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: occurrences.map { prefix + $0.key })
        #endif
    }
}

#if canImport(UserNotifications)
import UserNotifications
#endif

import SwiftUI
import FavWidgetsCore

/// Talks to `/api/widgets/events` through the host's API channel.
struct EventsClient {
    let context: WidgetContext

    private struct ListResponse: Decodable { let events: [EventSummary] }
    private struct EventResponse: Decodable { let event: EventSummary }
    private struct PreviewResponse: Decodable { let preview: EventInvitePreview }
    struct JoinResponse: Decodable { let event: EventSummary; let joined: Bool; let coinCredited: Bool }
    private struct PhotosResponse: Decodable { let photos: [EventPhoto] }
    private struct PhotoResponse: Decodable { let photo: EventPhoto }
    private struct PlaceResponse: Decodable { let place: EventPlace }
    struct SaveResponse: Decodable { let place: EventPlace; let circleId: String; let alreadySaved: Bool }
    private struct OK: Decodable { let success: Bool }

    func list() async throws -> [EventSummary] {
        let r: ListResponse = try await context.api(.get, "widgets/events"); return r.events
    }
    func create(name: String, emoji: String) async throws -> EventSummary {
        let r: EventResponse = try await context.api(.post, "widgets/events", body: ["name": name, "emoji": emoji]); return r.event
    }
    func detail(_ id: String) async throws -> EventDetail {
        try await context.api(.get, "widgets/events/\(id)")
    }
    func preview(token: String) async throws -> EventInvitePreview {
        let r: PreviewResponse = try await context.api(.get, "widgets/events/invite/\(token)"); return r.preview
    }
    func join(token: String) async throws -> JoinResponse {
        try await context.api(.post, "widgets/events/join", body: ["token": token])
    }
    func update(_ id: String, _ body: [String: Any]) async throws -> EventSummary {
        let r: EventResponse = try await context.api(.put, "widgets/events/\(id)", body: body); return r.event
    }
    func resetLink(_ id: String) async throws -> EventSummary {
        let r: EventResponse = try await context.api(.post, "widgets/events/\(id)/link/reset"); return r.event
    }
    func end(_ id: String) async throws { let _: OK = try await context.api(.delete, "widgets/events/\(id)") }
    func leave(_ id: String) async throws { let _: OK = try await context.api(.post, "widgets/events/\(id)/leave") }
    func remove(_ id: String, member: String) async throws { let _: OK = try await context.api(.delete, "widgets/events/\(id)/members/\(member)") }
    private struct InviteResponse: Decodable { let invited: Int; let event: EventSummary? }
    func invite(_ id: String, userIds: [String]) async throws -> EventSummary? {
        let r: InviteResponse = try await context.api(.post, "widgets/events/\(id)/invite", body: ["userIds": userIds]); return r.event
    }
    func addPhotos(_ id: String, urls: [(full: URL, thumb: URL?)], challengeId: String? = nil) async throws -> [EventPhoto] {
        let r: PhotosResponse = try await context.api(.post, "widgets/events/\(id)/photos",
                                                      body: ["photos": urls.map { pair -> [String: Any] in
                                                          var p: [String: Any] = ["imageUrl": pair.full.absoluteString]
                                                          if let thumb = pair.thumb { p["thumbUrl"] = thumb.absoluteString }
                                                          if let challengeId { p["challengeId"] = challengeId }
                                                          return p
                                                      }])
        return r.photos
    }
    func deletePhoto(_ id: String, photo: String) async throws { let _: OK = try await context.api(.delete, "widgets/events/\(id)/photos/\(photo)") }
    func like(_ id: String, photo: String) async throws -> EventPhoto {
        let r: PhotoResponse = try await context.api(.post, "widgets/events/\(id)/photos/\(photo)/like"); return r.photo
    }
    func tag(_ id: String, place: WidgetPlaceCandidate) async throws -> EventPlace {
        let r: PlaceResponse = try await context.api(.post, "widgets/events/\(id)/places", body: [
            "name": place.name, "address": place.address ?? "", "lat": place.coordinate.latitude,
            "lng": place.coordinate.longitude, "category": place.category, "placeId": place.id, "isGlobal": place.isGlobal
        ])
        return r.place
    }
    func save(_ id: String, place: String) async throws -> SaveResponse {
        try await context.api(.post, "widgets/events/\(id)/places/\(place)/save")
    }
    func connect(userId: String) async throws { let _: OK = try await context.api(.post, "widgets/connect", body: ["targetUserId": userId]) }

    // MARK: Doing things together (2026-10-06)

    private struct WallResponse: Decodable { let posts: [EventWallPost]; let reactions: [String] }
    private struct PostResponse: Decodable { let post: EventWallPost }
    private struct SongsResponse: Decodable { let songs: [EventSong] }
    private struct SongResponse: Decodable { let song: EventSong }
    private struct ChallengesResponse: Decodable { let challenges: [EventChallenge] }
    private struct RecapResponse: Decodable { let recap: EventRecap }
    private struct PingResponse: Decodable { let pinged: Int }

    func wall(_ id: String) async throws -> (posts: [EventWallPost], reactions: [String]) {
        let r: WallResponse = try await context.api(.get, "widgets/events/\(id)/wall"); return (r.posts, r.reactions)
    }
    func post(_ id: String, text: String) async throws -> EventWallPost {
        let r: PostResponse = try await context.api(.post, "widgets/events/\(id)/wall", body: ["text": text]); return r.post
    }
    func deletePost(_ id: String, post: String) async throws { let _: OK = try await context.api(.delete, "widgets/events/\(id)/wall/\(post)") }
    func react(_ id: String, post: String, emoji: String) async throws -> EventWallPost {
        let r: PostResponse = try await context.api(.post, "widgets/events/\(id)/wall/\(post)/react", body: ["emoji": emoji]); return r.post
    }
    func songs(_ id: String) async throws -> [EventSong] {
        let r: SongsResponse = try await context.api(.get, "widgets/events/\(id)/songs"); return r.songs
    }
    func requestSong(_ id: String, title: String, artist: String?) async throws -> EventSong {
        var body: [String: Any] = ["title": title]
        if let artist, !artist.isEmpty { body["artist"] = artist }
        let r: SongResponse = try await context.api(.post, "widgets/events/\(id)/songs", body: body); return r.song
    }
    func vote(_ id: String, song: String) async throws -> EventSong {
        let r: SongResponse = try await context.api(.post, "widgets/events/\(id)/songs/\(song)/vote"); return r.song
    }
    func markPlayed(_ id: String, song: String, played: Bool) async throws -> EventSong {
        let r: SongResponse = try await context.api(.post, "widgets/events/\(id)/songs/\(song)/played", body: ["played": played]); return r.song
    }
    func deleteSong(_ id: String, song: String) async throws { let _: OK = try await context.api(.delete, "widgets/events/\(id)/songs/\(song)") }
    func addChallenges(_ id: String, _ list: [(emoji: String, text: String)]) async throws -> [EventChallenge] {
        let r: ChallengesResponse = try await context.api(.post, "widgets/events/\(id)/challenges",
                                                          body: ["challenges": list.map { ["emoji": $0.emoji, "text": $0.text] }])
        return r.challenges
    }
    func removeChallenge(_ id: String, challenge: String) async throws -> [EventChallenge] {
        let r: ChallengesResponse = try await context.api(.delete, "widgets/events/\(id)/challenges/\(challenge)"); return r.challenges
    }
    func startRollCall(_ id: String) async throws -> EventSummary {
        let r: EventResponse = try await context.api(.post, "widgets/events/\(id)/rollcall"); return r.event
    }
    func answerRollCall(_ id: String, spot: WidgetCoordinate?) async throws -> EventSummary {
        var body: [String: Any] = [:]
        if let spot { body["lat"] = spot.latitude; body["lng"] = spot.longitude }
        let r: EventResponse = try await context.api(.post, "widgets/events/\(id)/rollcall/here", body: body); return r.event
    }
    func pingMissing(_ id: String, userId: String? = nil) async throws -> Int {
        let r: PingResponse = try await context.api(.post, "widgets/events/\(id)/rollcall/ping",
                                                    body: userId.map { ["userId": $0] } ?? [:]); return r.pinged
    }
    func closeRollCall(_ id: String) async throws { let _: OK = try await context.api(.delete, "widgets/events/\(id)/rollcall") }
    func recap(_ id: String) async throws -> EventRecap {
        let r: RecapResponse = try await context.api(.get, "widgets/events/\(id)/recap"); return r.recap
    }
}

/// The user's events, shared by the card and the full view.
@MainActor
final class EventsStore: RemoteStore {
    @Published private(set) var events: [EventSummary] = []

    static func shared(in context: WidgetContext) -> EventsStore {
        context.transient("events.store") { EventsStore() }
    }

    func refresh(_ context: WidgetContext, force: Bool = false) async {
        let client = EventsClient(context: context)
        if force {
            await load { self.events = try await client.list() }
        } else {
            await loadIfNeeded(staleAfter: 60) { self.events = try await client.list() }
        }
    }

    func upsert(_ event: EventSummary) {
        if let i = events.firstIndex(where: { $0.id == event.id }) { events[i] = event } else { events.insert(event, at: 0) }
    }

    func remove(_ id: String) { events.removeAll { $0.id == id } }
}

/// One open event's photos/places/people, refreshed while on screen.
@MainActor
final class EventDetailModel: ObservableObject {
    @Published var detail: EventDetail?
    @Published var error: String?
    @Published var uploading: String?

    let eventId: String
    private let client: EventsClient

    init(eventId: String, context: WidgetContext) {
        self.eventId = eventId
        self.client = EventsClient(context: context)
    }

    func load() async {
        do { detail = try await client.detail(eventId); error = nil } catch { self.error = "Couldn't load the event. Pull to try again." }
    }

    var photos: [EventPhoto] { detail?.photos ?? [] }
    var places: [EventPlace] { detail?.places ?? [] }

    func replacePhoto(_ photo: EventPhoto) {
        guard let d = detail else { return }
        detail = EventDetail(event: d.event, photos: d.photos.map { $0.id == photo.id ? photo : $0 }, places: d.places)
    }
    func removePhoto(_ id: String) {
        guard let d = detail else { return }
        detail = EventDetail(event: d.event, photos: d.photos.filter { $0.id != id }, places: d.places)
    }
    func prependPhotos(_ photos: [EventPhoto]) {
        guard let d = detail else { return }
        detail = EventDetail(event: d.event, photos: photos + d.photos, places: d.places)
    }
    func upsertPlace(_ place: EventPlace) {
        guard let d = detail else { return }
        let places = d.places.contains(where: { $0.id == place.id }) ? d.places.map { $0.id == place.id ? place : $0 } : [place] + d.places
        detail = EventDetail(event: d.event, photos: d.photos, places: places)
    }
    func replaceEvent(_ event: EventSummary) {
        guard let d = detail else { return }
        detail = EventDetail(event: event, photos: d.photos, places: d.places)
    }
}

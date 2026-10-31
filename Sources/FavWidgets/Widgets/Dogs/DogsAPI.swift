import SwiftUI
import FavWidgetsCore

/// Talks to `/api/widgets/dogs` through the host's API channel.
struct DogsClient {
    let context: WidgetContext

    struct FeedPage: Decodable { let posts: [DogPost]; let hasMore: Bool? }
    struct DailyPage: Decodable { let items: [DailyDog]; let hasMore: Bool? }
    struct DogPage: Decodable { let dog: DogProfile; let posts: [DogPost]? }
    struct CommentPosted: Decodable { let comment: DogComment; let post: DogPost? }
    struct VideoStart: Decodable {
        struct URLs: Decodable { let video: String; let poster: String; let thumb: String }
        let videoId: String
        let uploadUrls: URLs
    }
    struct PlaceSaved: Decodable {
        let placeId: String?; let circleId: String?; let circleName: String?; let alreadySaved: Bool?
        /// Whether it sits in the dog spots circle (the server knows it by its flag, whatever it's called)
        let inDogSpots: Bool?
    }
    private struct DogResponse: Decodable { let dog: DogProfile }
    private struct PostResponse: Decodable { let post: DogPost }
    private struct CommentsResponse: Decodable { let comments: [DogComment] }
    private struct ItemResponse: Decodable { let item: DailyDog }
    private struct PrefsResponse: Decodable { let prefs: DogDailyPrefs }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func before(_ date: Date?) -> String {
        guard let date else { return "" }
        return "before=\(Self.iso.string(from: date).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
    }

    // MARK: Me + membership

    func me() async throws -> DogsMe { try await context.api(.get, "widgets/dogs/me") }
    func join() async throws { _ = try await context.apiData(.post, "widgets/dogs/join") }
    func leave() async throws { _ = try await context.apiData(.post, "widgets/dogs/leave") }

    // MARK: Dogs

    func createDog(_ dog: DogProfile) async throws -> DogProfile {
        let r: DogResponse = try await context.api(.post, "widgets/dogs/profiles", body: dog.body); return r.dog
    }
    func updateDog(_ dog: DogProfile) async throws -> DogProfile {
        let r: DogResponse = try await context.api(.put, "widgets/dogs/profiles/\(dog.id)", body: dog.body); return r.dog
    }
    func deleteDog(_ id: String) async throws { _ = try await context.apiData(.delete, "widgets/dogs/profiles/\(id)") }
    func dog(_ id: String) async throws -> DogPage { try await context.api(.get, "widgets/dogs/profiles/\(id)") }

    // MARK: Dog Park

    func feed(_ tab: DogFeedTab, before date: Date? = nil) async throws -> FeedPage {
        let more = before(date)
        return try await context.api(.get, "widgets/dogs/feed?tab=\(tab.rawValue)\(more.isEmpty ? "" : "&\(more)")")
    }
    func post(_ id: String) async throws -> DogPost {
        let r: PostResponse = try await context.api(.get, "widgets/dogs/posts/\(id)"); return r.post
    }
    func createPhotoPost(caption: String, dogIds: [String], photoUrl: URL, thumbUrl: URL?) async throws -> DogPost {
        var body: [String: Any] = ["caption": caption, "dogIds": dogIds, "photoUrl": photoUrl.absoluteString]
        if let thumbUrl { body["thumbUrl"] = thumbUrl.absoluteString }
        let r: PostResponse = try await context.api(.post, "widgets/dogs/posts", body: body); return r.post
    }
    func startVideo(durationSec: Double) async throws -> VideoStart {
        try await context.api(.post, "widgets/dogs/videos", body: ["durationSec": durationSec])
    }
    func finishVideo(_ videoId: String, caption: String, dogIds: [String]) async throws -> DogPost {
        let r: PostResponse = try await context.api(.post, "widgets/dogs/videos/\(videoId)/finish",
                                                    body: ["caption": caption, "dogIds": dogIds])
        return r.post
    }
    func deletePost(_ id: String) async throws { _ = try await context.apiData(.delete, "widgets/dogs/posts/\(id)") }
    func pet(_ id: String) async throws -> DogPost {
        let r: PostResponse = try await context.api(.post, "widgets/dogs/posts/\(id)/pet"); return r.post
    }
    func comments(_ id: String) async throws -> [DogComment] {
        let r: CommentsResponse = try await context.api(.get, "widgets/dogs/posts/\(id)/comments"); return r.comments
    }
    func comment(_ id: String, text: String) async throws -> CommentPosted {
        try await context.api(.post, "widgets/dogs/posts/\(id)/comments", body: ["text": text])
    }
    func deleteComment(_ id: String, comment: String) async throws {
        _ = try await context.apiData(.delete, "widgets/dogs/posts/\(id)/comments/\(comment)")
    }
    func report(_ id: String, reason: String) async throws {
        _ = try await context.apiData(.post, "widgets/dogs/posts/\(id)/report", body: ["reason": reason])
    }
    func block(_ userId: String) async throws { _ = try await context.apiData(.post, "widgets/dogs/block/\(userId)") }

    // MARK: Daily Dog

    func daily(before date: Date? = nil) async throws -> DailyPage {
        let more = before(date)
        return try await context.api(.get, "widgets/dogs/daily\(more.isEmpty ? "" : "?\(more)")")
    }
    func dailyItem(_ id: String) async throws -> DailyDog {
        let r: ItemResponse = try await context.api(.get, "widgets/dogs/daily/\(id)"); return r.item
    }
    func saveSettings(enabled: Bool? = nil, times: [String]? = nil) async throws -> DogDailyPrefs {
        var body: [String: Any] = [:]
        if let enabled { body["enabled"] = enabled }
        if let times { body["times"] = times }
        let r: PrefsResponse = try await context.api(.put, "widgets/dogs/settings", body: body); return r.prefs
    }

    // MARK: My dogs' extras

    /// Adds a place to the person's "Dog spots" circle.
    func savePlace(_ place: WidgetPlaceCandidate) async throws -> PlaceSaved {
        try await context.api(.post, "widgets/dogs/places/save", body: [
            "name": place.name, "address": place.address ?? "", "lat": place.coordinate.latitude,
            "lng": place.coordinate.longitude, "category": place.category, "placeId": place.id, "isGlobal": place.isGlobal
        ])
    }
}

/// Membership, my dogs, the Daily Dog settings and today's card, shared by
/// the card and the full view.
@MainActor
final class DogsStore: RemoteStore {
    @Published private(set) var me = DogsMe()
    /// The Dog Park, per tab
    @Published private(set) var feeds: [DogFeedTab: [DogPost]] = [:]
    @Published private(set) var hasMore: [DogFeedTab: Bool] = [:]
    @Published private(set) var loadingFeed: Set<DogFeedTab> = []
    @Published private(set) var feedError: String?
    @Published private(set) var daily: [DailyDog] = []
    @Published private(set) var dailyHasMore = false

    static func shared(in context: WidgetContext) -> DogsStore {
        context.transient("dogs.store") { DogsStore() }
    }

    func refresh(_ context: WidgetContext, force: Bool = false) async {
        let client = DogsClient(context: context)
        if force {
            await load { self.me = try await client.me() }
        } else {
            await loadIfNeeded(staleAfter: 120) { self.me = try await client.me() }
        }
    }

    func setMember(_ member: Bool) { me.member = member; markLoaded() }
    func setPrefs(_ prefs: DogDailyPrefs) { me.prefs = prefs }

    func upsertDog(_ dog: DogProfile) {
        if let i = me.dogs.firstIndex(where: { $0.id == dog.id }) { me.dogs[i] = dog } else { me.dogs.append(dog) }
    }

    func removeDog(_ id: String) { me.dogs.removeAll { $0.id == id } }

    // MARK: Feed

    func loadFeed(_ tab: DogFeedTab, context: WidgetContext, more: Bool = false) async {
        guard !loadingFeed.contains(tab) else { return }
        if more, hasMore[tab] != true { return }
        loadingFeed.insert(tab)
        defer { loadingFeed.remove(tab) }
        do {
            let page = try await DogsClient(context: context).feed(tab, before: more ? feeds[tab]?.last?.createdAt : nil)
            feeds[tab] = more ? (feeds[tab] ?? []) + page.posts.filter { p in !(feeds[tab] ?? []).contains { $0.id == p.id } } : page.posts
            hasMore[tab] = page.hasMore ?? false
            feedError = nil
        } catch {
            if let message = WidgetErrorText.message(for: error) { feedError = message }
        }
    }

    /// A post changed (pets, comments) everywhere it shows.
    func update(_ post: DogPost) {
        for tab in DogFeedTab.allCases {
            if let i = feeds[tab]?.firstIndex(where: { $0.id == post.id }) { feeds[tab]?[i] = post }
        }
        for i in daily.indices where daily[i].post?.id == post.id { daily[i].post = post }
        if me.today?.post?.id == post.id { me.today?.post = post }
    }

    func insertNew(_ post: DogPost) {
        feeds[.today, default: []].insert(post, at: 0)
    }

    func remove(postId: String) {
        for tab in DogFeedTab.allCases { feeds[tab]?.removeAll { $0.id == postId } }
    }

    /// After a block: nothing of theirs stays on screen.
    func remove(authorId: String) {
        for tab in DogFeedTab.allCases { feeds[tab]?.removeAll { $0.authorId == authorId } }
    }

    // MARK: Daily

    func loadDaily(context: WidgetContext, more: Bool = false) async {
        do {
            let page = try await DogsClient(context: context).daily(before: more ? daily.last.flatMap { $0.sentAt ?? DogDay.date($0.date) } : nil)
            daily = more ? daily + page.items.filter { i in !daily.contains { $0.id == i.id } } : page.items
            dailyHasMore = page.hasMore ?? false
        } catch {
            if let message = WidgetErrorText.message(for: error) { feedError = message }
        }
    }
}

/// Pet a post: flip it at once, then take the server's count.
@MainActor
enum DogPetting {
    static func pet(_ post: DogPost, store: DogsStore, context: WidgetContext, onChange: ((DogPost) -> Void)? = nil) {
        let optimistic = post.togglingPet()
        store.update(optimistic)
        onChange?(optimistic)
        context.host.haptic(optimistic.iPetted ? .success : .light)
        if optimistic.iPetted { context.track("dog_petted") }
        Task { @MainActor in
            do {
                let fresh = try await DogsClient(context: context).pet(post.id)
                store.update(fresh)
                onChange?(fresh)
            } catch {
                store.update(post)
                onChange?(post)
            }
        }
    }
}

/// Photos and video prep for Dog Park posts (reuses the Events pipeline).
@MainActor
enum DogPosting {
    static let maxVideoSeconds = 15.0

    static func postPhoto(_ image: PostcardPlatformImage, caption: String, dogIds: [String], context: WidgetContext) async throws -> DogPost {
        guard let jpeg = EventImagePrep.jpeg(image) else { throw WidgetAPIError(status: 400, message: "That photo couldn't be read.") }
        let full = try await context.host.uploadImage(jpeg)
        let thumb: URL? = if let small = EventImagePrep.thumbnail(image) { try? await context.host.uploadImage(small) } else { nil }
        return try await DogsClient(context: context).createPhotoPost(caption: caption, dogIds: dogIds, photoUrl: full, thumbUrl: thumb)
    }

    /// Checks the length, makes the 720p copy and posters, uploads through
    /// the signed URLs, then publishes.
    static func postVideo(_ movie: PickedMovie, caption: String, dogIds: [String], context: WidgetContext,
                          progress: @escaping (String) -> Void) async throws -> DogPost {
        defer { try? FileManager.default.removeItem(at: movie.url) }
        guard let seconds = await EventVideoPrep.duration(movie.url) else {
            throw WidgetAPIError(status: 400, message: "That video couldn't be read. Try another one.")
        }
        guard seconds <= maxVideoSeconds + 0.5 else {
            throw WidgetAPIError(status: 400, code: "video_too_long",
                                 message: "Dog Park clips are up to 15 seconds. Trim it in Photos (Edit) and try again.")
        }
        progress("Preparing video…")
        let prepared = try await EventVideoPrep.prepare(movie.url)
        defer { try? FileManager.default.removeItem(at: prepared.video) }
        let client = DogsClient(context: context)
        let slot = try await client.startVideo(durationSec: seconds)
        guard let videoURL = URL(string: slot.uploadUrls.video), let posterURL = URL(string: slot.uploadUrls.poster) else {
            throw WidgetAPIError(status: 500, message: "Couldn't start the upload. Try again.")
        }
        progress("Uploading video…")
        try await EventVideoPrep.put(prepared.video, to: videoURL, contentType: "video/mp4")
        try await EventVideoPrep.put(prepared.poster, to: posterURL, contentType: "image/jpeg")
        if let thumb = prepared.thumb, let thumbURL = URL(string: slot.uploadUrls.thumb) {
            try? await EventVideoPrep.put(thumb, to: thumbURL, contentType: "image/jpeg")
        }
        return try await client.finishVideo(slot.videoId, caption: caption, dogIds: dogIds)
    }
}

/// Error text for an alert: the server's words, or a friendly fallback.
enum DogErrors {
    static func message(_ error: Error, fallback: String = "Check your connection and try again.") -> String {
        if let api = error as? WidgetAPIError, !api.message.isEmpty { return api.message }
        return WidgetErrorText.message(for: error) ?? fallback
    }
}

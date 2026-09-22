import SwiftUI
import FavWidgetsCore

/// Inner Circle workouts: post a finished workout, read what the people
/// who put you in their Inner Circle have posted.
enum WorkoutFeedAPI {
    struct Post: Decodable, Identifiable, Equatable {
        let postId: String
        let userId: String
        let userName: String
        let avatarUrl: String?
        let summary: WorkoutShareSummary
        let createdAt: Date
        var id: String { postId }
    }

    private struct FeedResponse: Decodable { let posts: [Post] }

    private struct ShareBody: Encodable {
        let summary: WorkoutShareSummary
        let audienceListId: String?
    }

    /// `audienceListId` names one of the person's Inner Circle lists; nil
    /// means anyone on any of them.
    static func share(context: WidgetContext, summary: WorkoutShareSummary, audienceListId: String? = nil) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(ShareBody(summary: summary, audienceListId: audienceListId))
        _ = try await context.host.request(WidgetAPIRequest(.post, "widgets/workouts/share", body: body))
    }

    /// One of the person's own named lists, as the audience menu shows it.
    struct AudienceList: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let userIds: [String]
        var count: Int { userIds.count }
    }

    private struct ListsEnvelope: Decodable {
        struct Data: Decodable { let lists: [AudienceList]? }
        let data: Data
    }

    /// The lists worth offering: the ones with someone on them.
    static func audienceLists(context: WidgetContext) async throws -> [AudienceList] {
        let envelope = try WidgetJSON.decode(ListsEnvelope.self, from: await context.host.request(WidgetAPIRequest(.get, "users/me/inner-circle/lists")))
        return (envelope.data.lists ?? []).filter { !$0.userIds.isEmpty }
    }

    static func feed(context: WidgetContext) async throws -> [Post] {
        try WidgetJSON.decode(FeedResponse.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/workouts/feed"))).posts
    }
}

@MainActor
final class WorkoutFeedStore: RemoteStore {
    @Published var posts: [WorkoutFeedAPI.Post] = []

    static func shared(_ context: WidgetContext) -> WorkoutFeedStore {
        context.transient("workouts.feed") { WorkoutFeedStore() }
    }

    /// Refetches after two minutes; sooner is just noise.
    func loadIfStale(context: WidgetContext) async {
        await loadIfNeeded(staleAfter: 120) { self.posts = try await WorkoutFeedAPI.feed(context: context) }
    }

    func load(context: WidgetContext) async {
        await load { self.posts = try await WorkoutFeedAPI.feed(context: context) }
    }
}

/// The person's Inner Circle lists, for choosing who a workout goes to.
@MainActor
final class WorkoutAudienceStore: RemoteStore {
    @Published var lists: [WorkoutFeedAPI.AudienceList] = []

    static func shared(_ context: WidgetContext) -> WorkoutAudienceStore {
        context.transient("workouts.audience") { WorkoutAudienceStore() }
    }

    func loadIfStale(context: WidgetContext) async {
        await loadIfNeeded(staleAfter: 300) { self.lists = try await WorkoutFeedAPI.audienceLists(context: context) }
    }
}

/// "Following": what your Inner Circle has been lifting.
struct WorkoutFollowingSection: View {
    let context: WidgetContext
    @ObservedObject var store: WorkoutFeedStore

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        Group {
            WidgetUI.header("Inner Circle", theme: theme)
                .padding(.top, 8)
                .listRowSeparator(.hidden)
            if store.posts.isEmpty {
                Text(store.isLoading ? "Loading…" : "Workouts shared by people who put you in their Inner Circle show up here. Manage your own list in Settings → Privacy → Inner Circle.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
            }
            ForEach(store.posts) { post in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        AsyncImage(url: post.avatarUrl.flatMap(URL.init(string:))) { phase in
                            if case .success(let image) = phase { image.resizable().scaledToFill() } else {
                                ZStack {
                                    Circle().fill(context.accent.opacity(0.15))
                                    Text(String(post.userName.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(context.accent)
                                }
                            }
                        }
                        .frame(width: 34, height: 34).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(post.userName) · \(post.summary.name)").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                            Text(headline(post)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                        }
                        Spacer()
                    }
                    ForEach(Array(post.summary.exercises.prefix(4).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 6) {
                            Text(line.name).font(.system(size: 13)).foregroundStyle(theme.label)
                            Spacer()
                            Text(line.bestSet + (line.isPR ? " 🏆" : "")).font(.system(size: 13, design: .rounded)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    ForEach(Array(post.summary.cardio.prefix(2).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 6) {
                            Text(line.name).font(.system(size: 13)).foregroundStyle(theme.label)
                            Spacer()
                            Text(line.detail).font(.system(size: 13, design: .rounded)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
                .listRowSeparator(.hidden)
            }
        }
        .listRowBackground(Color.clear)
        .task { await store.loadIfStale(context: context) }
    }

    private func headline(_ post: WorkoutFeedAPI.Post) -> String {
        var parts = [WorkoutFormat.relativeDay(post.createdAt, calendar: context.calendar), "\(max(1, post.summary.durationSeconds / 60)) min"]
        if post.summary.completedSets > 0 { parts.append("\(post.summary.completedSets) sets") }
        if post.summary.cardioMinutes > 0 { parts.append("\(post.summary.cardioMinutes) min cardio") }
        if post.summary.prCount > 0 { parts.append("\(post.summary.prCount) PR\(post.summary.prCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

import SwiftUI
import FavWidgetsCore

/// Shout-outs and toasts for the group ("Happy birthday Brit! 🎉"), with
/// emoji reactions. Members only.
struct EventWallSection: View {
    let context: WidgetContext
    let event: EventSummary
    @State private var posts: [EventWallPost] = []
    @State private var reactions: [String] = ["❤️", "😂", "🔥", "🎉", "👏", "🙌"]
    @State private var draft = ""
    @State private var loaded = false
    @State private var sending = false

    private var client: EventsClient { EventsClient(context: context) }

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                WidgetUI.textField("Say something to the group…", text: $draft, theme: theme, height: 44)
                Button { send() } label: {
                    Image(systemName: "paperplane.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(context.accent))
                }
                .buttonStyle(.plain)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if loaded && posts.isEmpty {
                Text("No shout-outs yet. Start one — a toast, a birthday wish, a \"where's the bus?\"")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            ForEach(posts) { post in postRow(post, theme: theme) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func postRow(_ post: EventWallPost, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(post.authorName).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.label)
                Spacer()
                if let at = post.createdAt.flatMap(EventTimes.date) {
                    Text(at.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            Text(post.text).font(.system(size: 16)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reactions, id: \.self) { emoji in
                        let r = post.reactions.first { $0.emoji == emoji }
                        Button { react(post, emoji) } label: {
                            Text(r.map { "\(emoji) \($0.count)" } ?? emoji)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(r?.mine == true ? context.accent.opacity(0.25) : theme.tertiaryBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        .contextMenu {
            if post.canDelete {
                Button(role: .destructive) { delete(post) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func load() async {
        if let r = try? await client.wall(event.id) { posts = r.posts; if !r.reactions.isEmpty { reactions = r.reactions } }
        loaded = true
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            if let post = try? await client.post(event.id, text: text) {
                posts.insert(post, at: 0); draft = ""
                context.host.haptic(.success)
                context.track("event_wall_post")
            } else {
                context.host.presentAlert(WidgetAlert(title: "Couldn't post", message: "Check your connection and try again."))
            }
        }
    }

    private func react(_ post: EventWallPost, _ emoji: String) {
        context.host.haptic(.selection)
        Task { @MainActor in
            if let updated = try? await client.react(event.id, post: post.id, emoji: emoji),
               let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = updated }
        }
    }

    private func delete(_ post: EventWallPost) {
        Task { @MainActor in
            if (try? await client.deletePost(event.id, post: post.id)) != nil { posts.removeAll { $0.id == post.id } }
        }
    }
}

/// Anyone adds a song; everyone upvotes; the coordinator (the DJ) marks
/// what's been played. The queue is ordered by votes.
struct EventSongsSection: View {
    let context: WidgetContext
    let event: EventSummary
    @State private var songs: [EventSong] = []
    @State private var title = ""
    @State private var artist = ""
    @State private var loaded = false
    @State private var adding = false

    private var client: EventsClient { EventsClient(context: context) }

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 14) {
            if !event.hasEnded {
                VStack(spacing: 8) {
                    WidgetUI.textField("Song", text: $title, theme: theme, height: 44)
                    HStack(spacing: 8) {
                        WidgetUI.textField("Artist (optional)", text: $artist, theme: theme, height: 44)
                        Button { add() } label: {
                            Text("Request").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(height: 44)
                                .background(Capsule().fill(context.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(adding || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if songs.isEmpty {
                Text("No requests yet. Add the song you want next — the most-voted plays first.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(songs) { song in row(song, theme: theme) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ song: EventSong, theme: WidgetTheme) -> some View {
        HStack(spacing: 12) {
            Button { vote(song) } label: {
                VStack(spacing: 0) {
                    Image(systemName: song.votedByMe ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    Text("\(song.votes)").font(.system(size: 13, weight: .bold)).monospacedDigit()
                }
                .foregroundStyle(song.votedByMe ? context.accent : theme.secondaryLabel)
                .frame(width: 36)
            }
            .buttonStyle(.plain)
            .disabled(song.played)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(song.played ? theme.secondaryLabel : theme.label)
                    .strikethrough(song.played)
                Text([song.artist, "added by \(song.addedByName)"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            if song.played { Text("Played").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel) }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if song.canManage {
                Button { markPlayed(song, !song.played) } label: {
                    Label(song.played ? "Not played yet" : "Mark as played", systemImage: song.played ? "arrow.uturn.backward" : "checkmark.circle")
                }
                Button(role: .destructive) { delete(song) } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }

    private func load() async {
        if let s = try? await client.songs(event.id) { songs = s }
        loaded = true
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces), a = artist.trimmingCharacters(in: .whitespaces)
        adding = true
        Task { @MainActor in
            defer { adding = false }
            if (try? await client.requestSong(event.id, title: t, artist: a.isEmpty ? nil : a)) != nil {
                title = ""; artist = ""
                context.host.haptic(.success)
                context.track("event_song_requested")
                await load()
            } else {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add the song", message: "Check your connection and try again."))
            }
        }
    }

    private func vote(_ song: EventSong) {
        context.host.haptic(.selection)
        Task { @MainActor in if (try? await client.vote(event.id, song: song.id)) != nil { await load() } }
    }

    private func markPlayed(_ song: EventSong, _ played: Bool) {
        Task { @MainActor in if (try? await client.markPlayed(event.id, song: song.id, played: played)) != nil { await load() } }
    }

    private func delete(_ song: EventSong) {
        Task { @MainActor in if (try? await client.deleteSong(event.id, song: song.id)) != nil { songs.removeAll { $0.id == song.id } } }
    }
}

/// Server timestamps (ISO 8601, with or without fractional seconds).
enum EventTimes {
    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}

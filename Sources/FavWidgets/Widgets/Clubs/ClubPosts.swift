import SwiftUI
import PhotosUI
import FavWidgetsCore

/// One bulletin announcement or board post, with reactions and replies.
struct ClubPostRow: View {
    let context: WidgetContext
    let post: ClubPost
    var onOpen: (() -> Void)?
    let onReact: (String?) -> Void

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClubAvatar(name: post.authorName, url: post.authorAvatar, size: 30, theme: theme)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.authorName).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                    if let at = post.createdAt {
                        Text(at.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                Spacer()
                if post.isBulletin { Image(systemName: "megaphone.fill").foregroundStyle(context.accent) }
            }
            Text(post.text).font(.system(size: 15)).foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            if let url = post.photoURL {
                CachedRemoteImage(url: url) { $0.resizable().scaledToFill() } placeholder: { theme.tertiaryBackground }
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(ClubCopy.reactionChoices, id: \.self) { emoji in
                        Button(emoji) { onReact(emoji == post.myReaction ? nil : emoji) }
                    }
                    if post.myReaction != nil { Button("Remove my reaction", role: .destructive) { onReact(nil) } }
                } label: {
                    Image(systemName: post.myReaction == nil ? "face.smiling" : "face.smiling.inverse")
                        .foregroundStyle(post.myReaction == nil ? theme.secondaryLabel : context.accent)
                }
                ForEach(post.reactions, id: \.emoji) { r in
                    Button { onReact(r.mine ? nil : r.emoji) } label: {
                        Text("\(r.emoji) \(r.count)").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(r.mine ? context.accent.opacity(0.22) : theme.tertiaryBackground))
                            .foregroundStyle(theme.label)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let onOpen {
                    Button(action: onOpen) {
                        Label(ClubCopy.replies(post.replyCount), systemImage: "bubble.left")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }
}

/// A small round avatar (photo, or the first letter).
struct ClubAvatar: View {
    let name: String
    let url: String?
    let size: CGFloat
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            Circle().fill(theme.tertiaryBackground)
            if let url, let parsed = URL(string: url) {
                CachedRemoteImage(url: parsed) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Write a bulletin announcement (organizers; everyone is notified) or a
/// board post (anyone), with an optional photo.
struct ClubPostComposer: View {
    let context: WidgetContext
    let club: Club
    /// "bulletin" | "board"
    let kind: String
    let onPosted: (ClubPost) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var photo: PostcardPlatformImage?
    @State private var busy = false

    private var isBulletin: Bool { kind == "bulletin" }

    var body: some View {
        let theme = context.theme
        let valid = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        WidgetSheet(title: isBulletin ? "Announcement" : "Post to the board", theme: theme,
                    confirm: (label: busy ? "Posting…" : "Post", enabled: valid && !busy, action: post), cancelDisabled: busy) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(isBulletin ? "Route change, cancellations, news…" : "Say something to the club", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    if let photo {
                        ZStack(alignment: .topTrailing) {
                            Image(postcardImage: photo).resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button { self.photo = nil; item = nil } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white).shadow(radius: 2)
                            }
                            .padding(8)
                        }
                    }
                    PhotosPicker(selection: $item, matching: .images) {
                        Label(photo == nil ? "Add a photo" : "Change photo", systemImage: "photo")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    Text(isBulletin
                         ? "Everyone in \(club.name) gets a notification (unless they muted the club)."
                         : "Everyone in the club can see the board. Nobody gets a notification for a board post.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
        .onChange(of: item) { picked in
            guard let picked else { return }
            Task { @MainActor in
                if let data = try? await picked.loadTransferable(type: Data.self) { photo = PostcardPlatformImage(data: data) }
            }
        }
    }

    private func post() {
        busy = true
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { busy = false }
            do {
                var url: URL?
                if let photo, let jpeg = EventImagePrep.jpeg(photo) { url = try await context.host.uploadImage(jpeg) }
                let created = try await ClubsClient(context: context).post(club.id, kind: kind, text: body, photoUrl: url)
                context.host.haptic(.success)
                context.track(isBulletin ? "club_bulletin_posted" : "club_board_posted")
                dismiss()
                onPosted(created)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't post", message: (error as NSError).localizedDescription))
            }
        }
    }
}

/// A post and its replies; reply at the bottom.
struct ClubThreadView: View {
    let context: WidgetContext
    let club: Club
    @State var post: ClubPost
    /// The post changed (reactions, reply count) or was deleted (nil)
    let onChange: (ClubPost?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var replies: [ClubReply] = []
    @State private var loaded = false
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ClubPostRow(context: context, post: post, onOpen: nil) { react($0) }
                        if !loaded { ProgressView().frame(maxWidth: .infinity) }
                        ForEach(replies) { reply in
                            HStack(alignment: .top, spacing: 8) {
                                ClubAvatar(name: reply.authorName, url: reply.authorAvatar, size: 26, theme: theme)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(reply.authorName).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.label)
                                        if let at = reply.createdAt {
                                            Text(at.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                                        }
                                    }
                                    Text(reply.text).font(.system(size: 15)).foregroundStyle(theme.label)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .contextMenu {
                                if reply.canDelete {
                                    Button("Delete reply", role: .destructive) { deleteReply(reply) }
                                }
                            }
                        }
                        if loaded && replies.isEmpty {
                            Text("No replies yet.").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 8) {
                    TextField("Reply to \(ClubCopy.firstName(post.authorName))", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.tertiaryBackground))
                    Button { send() } label: {
                        if sending { ProgressView().frame(width: 34, height: 34) } else {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                                .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.secondaryLabel : context.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send reply")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(theme.background)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(post.isBulletin ? "Announcement" : "Board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if post.canDelete {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) { deletePost() } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete post")
                    }
                }
            }
        }
        .task { await loadReplies() }
    }

    private var client: ClubsClient { ClubsClient(context: context) }

    private func loadReplies() async {
        do { replies = try await client.replies(club.id, post: post.id) } catch {}
        loaded = true
    }

    private func react(_ emoji: String?) {
        Task { @MainActor in
            if let updated = try? await client.react(club.id, post: post.id, emoji: emoji) {
                post = updated
                onChange(updated)
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let result = try await client.reply(club.id, post: post.id, text: text)
                replies.append(result.reply)
                draft = ""
                if let updated = result.post { post = updated; onChange(updated) }
                context.host.haptic(.success)
                context.track("club_replied")
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func deleteReply(_ reply: ClubReply) {
        Task { @MainActor in
            do {
                try await client.deleteReply(club.id, post: post.id, reply: reply.id)
                replies.removeAll { $0.id == reply.id }
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't delete it", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func deletePost() {
        Task { @MainActor in
            do {
                try await client.deletePost(club.id, post: post.id)
                onChange(nil)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't delete it", message: (error as NSError).localizedDescription))
            }
        }
    }
}

/// Every bulletin announcement or board post, newest first, paged.
struct ClubPostListView: View {
    let context: WidgetContext
    let club: Club
    /// "bulletin" | "board"
    let kind: String
    @Environment(\.dismiss) private var dismiss
    @State private var posts: [ClubPost] = []
    @State private var hasMore = true
    @State private var loading = false
    @State private var composing = false
    @State private var thread: ClubPost?

    private var canPost: Bool { kind == "board" || club.canOrganize }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(posts) { post in
                        ClubPostRow(context: context, post: post, onOpen: { thread = post }) { react(post, $0) }
                            .onAppear { if post.id == posts.last?.id { Task { await loadMore() } } }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if !loading && posts.isEmpty {
                        Text(kind == "board" ? "Nothing on the board yet. Start the conversation." : "No announcements yet.")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(16)
            }
            .refreshable { await reload() }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(kind == "board" ? "Board" : "Bulletin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if canPost {
                    ToolbarItem(placement: .primaryAction) {
                        Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel(kind == "board" ? "New post" : "New announcement")
                    }
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $composing) {
            ClubPostComposer(context: context, club: club, kind: kind) { posts.insert($0, at: 0) }
        }
        .sheet(item: $thread) { post in
            ClubThreadView(context: context, club: club, post: post) { updated in
                if let updated { replace(updated) } else { posts.removeAll { $0.id == post.id } }
            }
        }
    }

    private var client: ClubsClient { ClubsClient(context: context) }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let page = try? await client.posts(club.id, kind: kind) {
            posts = page.posts
            hasMore = page.hasMore ?? false
        }
    }

    private func loadMore() async {
        guard hasMore, !loading, let last = posts.last?.createdAt else { return }
        loading = true
        defer { loading = false }
        if let page = try? await client.posts(club.id, kind: kind, before: last) {
            posts += page.posts.filter { p in !posts.contains { $0.id == p.id } }
            hasMore = page.hasMore ?? false
        }
    }

    private func react(_ post: ClubPost, _ emoji: String?) {
        Task { @MainActor in
            if let updated = try? await client.react(club.id, post: post.id, emoji: emoji) { replace(updated) }
        }
    }

    private func replace(_ post: ClubPost) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = post }
    }
}

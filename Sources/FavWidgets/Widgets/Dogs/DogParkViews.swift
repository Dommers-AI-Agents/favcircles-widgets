import SwiftUI
import PhotosUI
import AVKit
import FavWidgetsCore

/// The Dog Park: everyone's dogs, newest today / most-petted this week /
/// people you follow. Post at the top, pet anything.
struct DogParkView: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    let onOpen: (DogPost) -> Void
    let onAddDog: () -> Void
    @State private var feedTab: DogFeedTab = .today
    @State private var composing = false

    var body: some View {
        let theme = context.theme
        let posts = store.feeds[feedTab] ?? []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                composeBar(theme)
                HStack(spacing: 8) {
                    ForEach(DogFeedTab.allCases) { t in
                        DogChip(title: t.label, selected: t == feedTab, accent: context.accent, theme: theme) { feedTab = t }
                    }
                }
                if posts.isEmpty {
                    if store.loadingFeed.contains(feedTab) {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        empty(theme)
                    }
                }
                ForEach(posts) { post in
                    DogPostCard(context: context, store: store, post: post, onOpen: { onOpen(post) })
                        .onAppear {
                            if post.id == posts.last?.id { Task { await store.loadFeed(feedTab, context: context, more: true) } }
                        }
                }
                if store.loadingFeed.contains(feedTab), !posts.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if let error = store.feedError, posts.isEmpty {
                    Text(error).font(.system(size: 13)).foregroundStyle(theme.warning)
                }
            }
            .padding(16)
        }
        .refreshable { await store.loadFeed(feedTab, context: context) }
        .task(id: feedTab) {
            if store.feeds[feedTab] == nil { await store.loadFeed(feedTab, context: context) }
        }
        .sheet(isPresented: $composing) {
            DogPostComposer(context: context, dogs: store.me.dogs, onAddDog: onAddDog) { post in
                store.insertNew(post)
                feedTab = .today
            }
        }
    }

    private func composeBar(_ theme: WidgetTheme) -> some View {
        Button { composing = true } label: {
            HStack(spacing: 12) {
                Text("📸").font(.system(size: 26))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.me.dogs.first.map { "Post \($0.name)" } ?? "Post a dog").font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("A photo or a 15-second clip. Collect pets.").font(.system(size: 13)).opacity(0.9)
                }
                .foregroundStyle(.white)
                Spacer()
                Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(.white)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [context.accent, Color(red: 0.95, green: 0.42, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }

    private func empty(_ theme: WidgetTheme) -> some View {
        VStack(spacing: 10) {
            Text("🐕").font(.system(size: 54))
            Text(DogCopy.emptyFeed(feedTab)).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// One post in the feed: who, the picture (double-tap to pet), the Pet
/// button, comments.
struct DogPostCard: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    let post: DogPost
    let onOpen: () -> Void
    @State private var burst = 0

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            DogAuthorLine(context: context, post: post)
            ZStack {
                DogPostMedia(post: post, theme: theme, height: 300, playsInline: false)
                    .onTapGesture(count: 2) { petFromDoubleTap() }
                    .onTapGesture { onOpen() }
                DogPawBurst(trigger: burst, accent: context.accent)
            }
            if !post.caption.isEmpty {
                Text(post.caption).font(.system(size: 15)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                DogPetButton(context: context, post: post) {
                    if !post.iPetted { burst += 1 }
                    DogPetting.pet(post, store: store, context: context)
                }
                Spacer()
                Button(action: onOpen) {
                    Label(DogCopy.comments(post.commentCount), systemImage: "bubble.left")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.secondaryBackground))
    }

    /// Instagram habit: a double tap pets (never un-pets).
    private func petFromDoubleTap() {
        burst += 1
        guard !post.iPetted else { context.host.haptic(.light); return }
        DogPetting.pet(post, store: store, context: context)
    }
}

/// Avatar, name, when, and which dogs.
struct DogAuthorLine: View {
    let context: WidgetContext
    let post: DogPost

    var body: some View {
        let theme = context.theme
        HStack(spacing: 8) {
            ClubAvatar(name: post.authorName, url: post.authorPhotoUrl, size: 32, theme: theme)
            VStack(alignment: .leading, spacing: 1) {
                Text(post.dogNames.map { "\($0) · \(post.authorName)" } ?? post.authorName)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                if let at = post.createdAt {
                    Text(at.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                }
            }
            Spacer()
            if post.isVideo { Image(systemName: "video.fill").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
        }
    }
}

/// The picture, or the clip (a poster with a play badge in the feed; plays
/// on the post page).
struct DogPostMedia: View {
    let post: DogPost
    let theme: WidgetTheme
    let height: CGFloat
    let playsInline: Bool

    var body: some View {
        Group {
            if playsInline, post.isVideo, let url = post.videoUrl.flatMap(URL.init(string:)) {
                DogVideoPlayer(url: url)
            } else {
                CachedRemoteImage(url: post.displayURL) { $0.resizable().scaledToFill() } placeholder: {
                    ZStack {
                        theme.tertiaryBackground
                        Image(systemName: "pawprint.fill").font(.system(size: 34)).foregroundStyle(theme.secondaryLabel.opacity(0.4))
                    }
                }
                .overlay {
                    if post.isVideo {
                        Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white.opacity(0.92)).shadow(radius: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Plays a clip, looping, muted until tapped.
struct DogVideoPlayer: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player { VideoPlayer(player: player) } else { ProgressView() }
        }
        .onAppear {
            guard player == nil else { player?.play(); return }
            let queue = AVQueuePlayer()
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            queue.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// The Pet button: a paw that pats, and the count.
struct DogPetButton: View {
    let context: WidgetContext
    let post: DogPost
    let action: () -> Void
    @State private var pat = false

    var body: some View {
        Button {
            pat = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pat = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: post.iPetted ? "pawprint.fill" : "pawprint")
                    .font(.system(size: 20, weight: .semibold))
                    .rotationEffect(.degrees(pat ? -25 : 0))
                    .scaleEffect(pat ? 1.35 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.4), value: pat)
                Text(post.iPetted ? (post.petCount <= 1 ? "Petted!" : DogCopy.petted(post.petCount)) : (post.petCount == 0 ? "Pet" : DogCopy.petted(post.petCount)))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(post.iPetted ? .white : context.accent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(post.iPetted ? context.accent : context.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(post.iPetted ? "Petted. Tap to un-pet." : "Pet this dog")
    }
}

/// Paws float up over the picture when it's petted.
struct DogPawBurst: View {
    let trigger: Int
    let accent: Color
    @State private var shown = false
    @State private var cheer = ""

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: CGFloat(22 + i * 6)))
                    .foregroundStyle(i % 2 == 0 ? .white : accent)
                    .shadow(color: .black.opacity(0.25), radius: 3)
                    .offset(x: CGFloat(i * 34 - 68), y: shown ? -CGFloat(70 + i * 12) : 30)
                    .rotationEffect(.degrees(Double(i * 14 - 28)))
                    .opacity(shown ? 0 : 1)
            }
            Text(cheer).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4)
                .scaleEffect(shown ? 1.1 : 0.6)
                .opacity(shown ? 0 : 1)
        }
        .opacity(trigger == 0 ? 0 : 1)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _ in
            cheer = DogCopy.petCheers.randomElement() ?? "Good dog!"
            shown = false
            withAnimation(.easeOut(duration: 0.9)) { shown = true }
        }
    }
}

/// Post a photo or a clip of up to 15 seconds, and which dogs it shows.
struct DogPostComposer: View {
    let context: WidgetContext
    let dogs: [DogProfile]
    let onAddDog: () -> Void
    let onPosted: (DogPost) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var item: PhotosPickerItem?
    @State private var photo: PostcardPlatformImage?
    @State private var movie: PickedMovie?
    @State private var moviePoster: PostcardPlatformImage?
    @State private var chosen: Set<String> = []
    @State private var busy: String?

    var body: some View {
        let theme = context.theme
        let ready = (photo != nil || movie != nil) && busy == nil
        WidgetSheet(title: "Post to the Dog Park", theme: theme,
                    confirm: (label: busy ?? "Post", enabled: ready, action: post), cancelDisabled: busy != nil) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    picker(theme)
                    TextField("Say something about this good dog", text: $caption, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    if dogs.isEmpty {
                        Button { dismiss(); onAddDog() } label: {
                            Label("Add your dog so posts show their name", systemImage: "plus.circle")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        WidgetUI.header("Who's in it?", theme: theme)
                        FlowChips(items: dogs) { dog in
                            DogChip(title: "🐶 \(dog.name)", selected: chosen.contains(dog.id), accent: context.accent, theme: theme) {
                                if chosen.contains(dog.id) { chosen.remove(dog.id) } else if chosen.count < 3 { chosen.insert(dog.id) }
                            }
                        }
                    }
                    Text("Everyone in the Dog Park can see it. Keep it about the dogs 🐾")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                .padding(16)
            }
        }
        .interactiveDismissDisabled(busy != nil)
        .onAppear { if dogs.count == 1 { chosen = [dogs[0].id] } }
        .onChange(of: item) { picked in
            guard let picked else { return }
            Task { @MainActor in await load(picked) }
        }
    }

    @ViewBuilder
    private func picker(_ theme: WidgetTheme) -> some View {
        let preview = photo ?? moviePoster
        let accent = context.accent
        PhotosPicker(selection: $item, matching: .any(of: [.images, .videos])) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.tertiaryBackground)
                if let preview {
                    Image(postcardImage: preview).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if movie != nil {
                        Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white).shadow(radius: 4)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 36)).foregroundStyle(accent)
                        Text("Pick a photo or a clip").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text("Videos up to 15 seconds").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
            .frame(height: 260)
        }
        .buttonStyle(.plain)
    }

    private func load(_ picked: PhotosPickerItem) async {
        photo = nil; moviePoster = nil
        if let old = movie { try? FileManager.default.removeItem(at: old.url) }
        movie = nil
        if picked.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            busy = "Loading…"
            defer { busy = nil }
            guard let m = try? await picked.loadTransferable(type: PickedMovie.self) else { return }
            if let seconds = await EventVideoPrep.duration(m.url), seconds > DogPosting.maxVideoSeconds + 0.5 {
                try? FileManager.default.removeItem(at: m.url)
                item = nil
                context.host.presentAlert(WidgetAlert(title: "That clip is \(Int(seconds.rounded())) seconds",
                                                      message: "Dog Park clips are up to 15 seconds. Trim it in Photos (Edit) and pick it again."))
                return
            }
            movie = m
            if let data = await EventVideoPrep.frame(m.url, maxSide: 900, quality: 0.7) { moviePoster = PostcardPlatformImage(data: data) }
        } else if let data = try? await picked.loadTransferable(type: Data.self) {
            photo = PostcardPlatformImage(data: data)
        }
    }

    private func post() {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let dogIds = dogs.map(\.id).filter { chosen.contains($0) }
        busy = "Posting…"
        Task { @MainActor in
            defer { busy = nil }
            do {
                let created: DogPost
                if let movie {
                    created = try await DogPosting.postVideo(movie, caption: text, dogIds: dogIds, context: context) { busy = $0 }
                    self.movie = nil
                } else if let photo {
                    created = try await DogPosting.postPhoto(photo, caption: text, dogIds: dogIds, context: context)
                } else { return }
                context.host.haptic(.success)
                context.track("dog_posted", ["kind": created.kind.rawValue])
                dismiss()
                onPosted(created)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't post", message: DogErrors.message(error)))
            }
        }
    }
}

/// One post: the clip plays, pets, comments, the dogs' cards, share,
/// report and block.
struct DogPostDetailView: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    @State var post: DogPost
    let onClose: () -> Void
    @State private var comments: [DogComment] = []
    @State private var loaded = false
    @State private var draft = ""
    @State private var sending = false
    @State private var burst = 0
    @State private var openDog: DogRefItem?
    @State private var confirming: Confirm?
    @State private var reporting = false

    struct DogRefItem: Identifiable { let id: String }
    enum Confirm: Identifiable {
        case block, delete
        var id: Int { self == .block ? 0 : 1 }
    }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DogAuthorLine(context: context, post: post)
                        ZStack {
                            DogPostMedia(post: post, theme: theme, height: 380, playsInline: true)
                                .onTapGesture(count: 2) { petFromDoubleTap() }
                            DogPawBurst(trigger: burst, accent: context.accent)
                        }
                        if !post.dogs.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(post.dogs) { dog in
                                    Button { openDog = DogRefItem(id: dog.id) } label: {
                                        Text("🐶 \(dog.name)").font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(context.accent.opacity(0.15)))
                                            .foregroundStyle(context.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !post.caption.isEmpty {
                            Text(post.caption).font(.system(size: 16)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            DogPetButton(context: context, post: post) {
                                if !post.iPetted { burst += 1 }
                                DogPetting.pet(post, store: store, context: context) { post = $0 }
                            }
                            Spacer()
                            Button { share() } label: {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(context.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                        Text(DogCopy.comments(post.commentCount) == "Comment" ? "No comments yet" : DogCopy.comments(post.commentCount))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                        if !loaded { ProgressView().frame(maxWidth: .infinity) }
                        ForEach(comments) { comment in commentRow(comment, theme: theme) }
                    }
                    .padding(16)
                }
                composer(theme)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(post.dogNames ?? "Dog Park")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) }
                ToolbarItem(placement: .primaryAction) { menu }
            }
        }
        .task { await loadComments() }
        .sheet(item: $openDog) { ref in
            DogProfileSheet(context: context, store: store, dogId: ref.id)
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if confirming == .block {
                Button("Block \(post.authorName)", role: .destructive) { block() }
            } else if confirming == .delete {
                Button("Delete post", role: .destructive) { delete() }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text(confirming == .block ? "You won't see their posts or comments, and they won't see yours." : "This can't be undone.")
        }
        .confirmationDialog("Report this post", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(["Not a dog / spam", "Mean or harmful", "Animal mistreatment", "Something else"], id: \.self) { reason in
                Button(reason) { report(reason) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll take a look. Thanks for keeping the Dog Park friendly.")
        }
    }

    private var confirmTitle: String { confirming == .block ? "Block \(post.authorName)?" : "Delete this post?" }

    private var menu: some View {
        Menu {
            Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
            if post.mine {
                Button(role: .destructive) { confirming = .delete } label: { Label("Delete post", systemImage: "trash") }
            } else {
                Button { reporting = true } label: { Label("Report", systemImage: "flag") }
                Button(role: .destructive) { confirming = .block } label: { Label("Block \(post.authorName)", systemImage: "hand.raised") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func commentRow(_ comment: DogComment, theme: WidgetTheme) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ClubAvatar(name: comment.authorName, url: comment.authorPhotoUrl, size: 26, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.authorName).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.label)
                    if let at = comment.createdAt {
                        Text(at.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                Text(comment.text).font(.system(size: 15)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if comment.mine || post.mine {
                Menu {
                    Button("Delete comment", role: .destructive) { deleteComment(comment) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(theme.secondaryLabel).padding(6)
                }
            }
        }
    }

    private func composer(_ theme: WidgetTheme) -> some View {
        HStack(spacing: 8) {
            TextField("Say something nice", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.secondaryBackground))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.background)
    }

    private func petFromDoubleTap() {
        burst += 1
        guard !post.iPetted else { context.host.haptic(.light); return }
        DogPetting.pet(post, store: store, context: context) { post = $0 }
    }

    private func loadComments() async {
        defer { loaded = true }
        if let list = try? await DogsClient(context: context).comments(post.id) { comments = list }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let r = try await DogsClient(context: context).comment(post.id, text: text)
                comments.append(r.comment)
                draft = ""
                post = r.post ?? { var p = post; p.commentCount += 1; return p }()
                store.update(post)
                context.track("dog_commented")
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't comment", message: DogErrors.message(error)))
            }
        }
    }

    private func deleteComment(_ comment: DogComment) {
        Task { @MainActor in
            do {
                try await DogsClient(context: context).deleteComment(post.id, comment: comment.id)
                comments.removeAll { $0.id == comment.id }
                post.commentCount = max(0, post.commentCount - 1)
                store.update(post)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't delete", message: DogErrors.message(error)))
            }
        }
    }

    private func share() {
        let content = DogsWidget.shareCardContent(post, image: nil)
        Task { @MainActor in
            var withImage = content
            withImage.imageJPEG = await DogShareImages.jpeg(post.thumbnailURL)
            context.track("dog_post_shared")
            context.host.share(WidgetShareKit.items(descriptor: context.descriptor, content: withImage))
        }
    }

    private func report(_ reason: String) {
        Task { @MainActor in
            do {
                try await DogsClient(context: context).report(post.id, reason: reason)
                context.host.presentAlert(WidgetAlert(title: "Thanks for telling us", message: "We'll take a look at this post."))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't report", message: DogErrors.message(error)))
            }
        }
    }

    private func block() {
        let authorId = post.authorId
        Task { @MainActor in
            do {
                try await DogsClient(context: context).block(authorId)
                store.remove(authorId: authorId)
                context.host.haptic(.success)
                onClose()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't block", message: DogErrors.message(error)))
            }
        }
    }

    private func delete() {
        Task { @MainActor in
            do {
                try await DogsClient(context: context).deletePost(post.id)
                store.remove(postId: post.id)
                onClose()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't delete", message: DogErrors.message(error)))
            }
        }
    }
}

/// A dog's card from the Dog Park: photo, breed, age, personality, posts.
struct DogProfileSheet: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    let dogId: String
    @Environment(\.dismiss) private var dismiss
    @State private var dog: DogProfile?
    @State private var posts: [DogPost] = []
    @State private var failed = false
    @State private var openPost: DogPost?

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                if let dog {
                    VStack(spacing: 12) {
                        DogAvatar(url: dog.photoURL, size: 140, accent: context.accent, theme: theme)
                        Text(dog.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
                        let sub = DogCopy.subtitle(dog)
                        if !sub.isEmpty { Text(sub).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel) }
                        if !dog.personality.isEmpty {
                            Text("“\(dog.personality)”").font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(theme.label)
                                .multilineTextAlignment(.center)
                        }
                        if !dog.ownerName.isEmpty {
                            Text("Human: \(dog.ownerName)").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                            ForEach(posts) { post in
                                Button { openPost = post } label: {
                                    WidgetUI.thumbnail(url: post.thumbnailURL, width: 110, height: 110, cornerRadius: 8, background: theme.tertiaryBackground,
                                                       fallbackSymbol: "pawprint.fill", fallbackColor: theme.secondaryLabel, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                } else if failed {
                    Text("This pup isn't here anymore.").font(.system(size: 16)).foregroundStyle(theme.secondaryLabel).padding(.top, 60)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            do {
                let page = try await DogsClient(context: context).dog(dogId)
                dog = page.dog
                posts = page.posts ?? []
            } catch { failed = true }
        }
        .sheet(item: $openPost) { post in
            DogPostDetailView(context: context, store: store, post: post) { openPost = nil }
        }
    }
}

/// A dog's round photo, or a paw.
struct DogAvatar: View {
    let url: URL?
    let size: CGFloat
    let accent: Color
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.15))
            if let url {
                CachedRemoteImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text("🐶").font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A pill that's filled when selected.
struct DogChip: View {
    let title: String
    let selected: Bool
    let accent: Color
    let theme: WidgetTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(selected ? accent : theme.tertiaryBackground))
                .foregroundStyle(selected ? .white : theme.label)
        }
        .buttonStyle(.plain)
    }
}

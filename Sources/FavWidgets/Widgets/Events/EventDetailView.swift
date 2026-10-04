import SwiftUI
import PhotosUI
import FavWidgetsCore

/// One event: the shared album, the places, the people. Members only.
struct EventDetailView: View {
    let context: WidgetContext
    let eventId: String
    let onGone: () -> Void
    let onChange: (EventSummary) -> Void

    @StateObject private var model: EventDetailModel
    @State private var tab = Tab.photos
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var cameraImage: PostcardPlatformImage?
    @State private var viewerStart: EventPhoto?
    @State private var showInvite = false
    @State private var renaming = false
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case photos = "Photos", places = "Places", people = "People" }

    init(context: WidgetContext, eventId: String, onGone: @escaping () -> Void, onChange: @escaping (EventSummary) -> Void) {
        self.context = context
        self.eventId = eventId
        self.onGone = onGone
        self.onChange = onChange
        _model = StateObject(wrappedValue: EventDetailModel(eventId: eventId, context: context))
    }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let event = model.detail?.event {
                        header(event, theme: theme)
                        actions(event, theme: theme)
                        Picker("Section", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch tab {
                        case .photos: photosSection(event, theme: theme)
                        case .places: EventPlacesSection(context: context, model: model, event: event)
                        case .people: EventPeopleSection(context: context, model: model, event: event, onGone: { dismiss(); onGone() })
                        }
                    } else if let error = model.error {
                        Text(error).foregroundStyle(theme.secondaryLabel).padding(.top, 60).frame(maxWidth: .infinity)
                    } else {
                        ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .refreshable { await model.load() }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(model.detail.map { "\($0.event.emoji) \($0.event.name)" } ?? "Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let event = model.detail?.event {
                    ToolbarItem(placement: .confirmationAction) { menu(event) }
                }
            }
            .overlay(alignment: .bottom) {
                if let uploading = model.uploading {
                    Text(uploading).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .padding(.bottom, 24)
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.detail?.event) { event in if let event { onChange(event) } }
        .onChange(of: pickedItems) { items in
            guard !items.isEmpty else { return }
            pickedItems = []
            Task { await uploadPicked(items) }
        }
        .onChange(of: cameraImage) { image in
            guard let image else { return }
            cameraImage = nil
            Task { await upload(images: [image]) }
        }
        .widgetCameraCover(isPresented: $showCamera) {
            #if os(iOS)
            PostcardCameraPicker(image: $cameraImage).ignoresSafeArea()
            #else
            EmptyView()
            #endif
        }
        .sheet(item: $viewerStart) { start in
            EventPhotoViewer(context: context, model: model, startId: start.id)
        }
        .sheet(isPresented: $showInvite) {
            if let event = model.detail?.event { EventInviteSheet(context: context, event: event) }
        }
        .alert("Rename event", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header

    private func header(_ event: EventSummary, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(event.emoji).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("\(EventCopy.memberCount(event.members.count)) · run by \(event.isHost ? "you" : event.hostName)")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
            }
            HStack(spacing: -8) {
                ForEach(event.members.prefix(8)) { member in EventAvatar(member: member, size: 32) }
                if event.members.count > 8 {
                    Text("+\(event.members.count - 8)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.25)))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.24, blue: 0.5), context.accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func actions(_ event: EventSummary, theme: WidgetTheme) -> some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 20, matching: .images) {
                actionLabel("Add photos", "photo.on.rectangle.angled", theme: theme)
            }
            #if os(iOS)
            if PostcardCameraPicker.isAvailable {
                Button { showCamera = true } label: { actionLabel("Camera", "camera.fill", theme: theme) }.buttonStyle(.plain)
            }
            #endif
            Button { showInvite = true } label: { actionLabel("Invite", "person.badge.plus", theme: theme) }
                .buttonStyle(.plain)
                .disabled(!event.joinOpen)
        }
    }

    private func actionLabel(_ title: String, _ symbol: String, theme: WidgetTheme) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .foregroundStyle(context.accent)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private func menu(_ event: EventSummary) -> some View {
        Menu {
            if event.isHost {
                Button { newName = event.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                Button { toggleJoin(event) } label: {
                    Label(event.joinOpen ? "Close joining" : "Open joining", systemImage: event.joinOpen ? "lock" : "lock.open")
                }
                Button { resetLink() } label: { Label("New invite link", systemImage: "arrow.triangle.2.circlepath") }
            }
            if !model.photos.isEmpty {
                Button { Task { await downloadAll() } } label: { Label("Download all photos", systemImage: "square.and.arrow.down.on.square") }
            }
        } label: { Image(systemName: "ellipsis.circle") }
    }

    // MARK: Photos

    @ViewBuilder
    private func photosSection(_ event: EventSummary, theme: WidgetTheme) -> some View {
        if model.photos.isEmpty {
            VStack(spacing: 8) {
                Text("📸").font(.system(size: 40))
                Text("No photos yet. Snap one or add some from your library. Only people in \(event.name) can see them.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(model.photos) { photo in
                    Button { viewerStart = photo } label: {
                        Color.gray.opacity(0.15)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                AsyncImage(url: URL(string: photo.imageUrl)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { ProgressView() }
                            )
                            .clipped()
                            .overlay(alignment: .bottomTrailing) {
                                if photo.likeCount > 0 {
                                    Text("♥ \(photo.likeCount)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.black.opacity(0.55))).padding(4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Uploading

    private func uploadPicked(_ items: [PhotosPickerItem]) async {
        var images: [PostcardPlatformImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data) {
                images.append(image)
            }
        }
        await upload(images: images)
    }

    private func upload(images: [PostcardPlatformImage]) async {
        guard !images.isEmpty else { return }
        var urls: [URL] = []
        for (i, image) in images.enumerated() {
            model.uploading = EventCopy.uploadProgress(done: i, total: images.count)
            guard let jpeg = EventImagePrep.jpeg(image) else { continue }
            if let url = try? await context.host.uploadImage(jpeg) { urls.append(url) }
        }
        defer { model.uploading = nil }
        guard !urls.isEmpty else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't add photos", message: "Check your connection and try again."))
            return
        }
        do {
            let added = try await EventsClient(context: context).addPhotos(eventId, urls: urls)
            model.prependPhotos(added)
            tab = .photos
            context.host.haptic(.success)
            context.track("event_photos_added", ["count": "\(added.count)"])
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't add photos", message: "Check your connection and try again."))
        }
    }

    private func downloadAll() async {
        let photos = model.photos
        var saved = 0
        for (i, photo) in photos.enumerated() {
            model.uploading = "Saving \(i + 1) of \(photos.count)…"
            guard let url = URL(string: photo.imageUrl),
                  let fetched = try? await URLSession.shared.data(from: url) else { continue }
            let data = fetched.0
            do { try await context.host.saveImageToPhotos(data); saved += 1 } catch {
                model.uploading = nil
                context.host.presentAlert(WidgetAlert(title: "Couldn't save to Photos", message: "Allow FavCircles to add photos in Settings, then try again."))
                return
            }
        }
        model.uploading = nil
        context.host.haptic(.success)
        context.host.presentAlert(WidgetAlert(title: "Saved", message: "\(saved) photo\(saved == 1 ? "" : "s") saved to your Photos."))
    }

    // MARK: Coordinator

    private func rename() {
        let name = newName
        Task { @MainActor in
            if let event = try? await EventsClient(context: context).update(eventId, ["name": name]) { model.replaceEvent(event) }
        }
    }

    private func toggleJoin(_ event: EventSummary) {
        Task { @MainActor in
            if let updated = try? await EventsClient(context: context).update(eventId, ["joinOpen": !event.joinOpen]) {
                model.replaceEvent(updated)
                context.host.haptic(.light)
            }
        }
    }

    private func resetLink() {
        Task { @MainActor in
            if let updated = try? await EventsClient(context: context).resetLink(eventId) {
                model.replaceEvent(updated)
                context.host.presentAlert(WidgetAlert(title: "New link", message: "The old link stopped working. Share the new one from Invite."))
            }
        }
    }
}

/// A member's face (or initial).
struct EventAvatar: View {
    let member: EventSummary.Member
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.9))
            if let url = member.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initial }
                    .clipShape(Circle())
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    private var initial: some View {
        Text(String(member.name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.purple)
    }
}

/// Phone photos are huge; the upload pipeline wants a sane JPEG.
enum EventImagePrep {
    static func jpeg(_ image: PostcardPlatformImage) -> Data? {
        #if os(iOS)
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / max(longest, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
        #else
        return nil
        #endif
    }
}

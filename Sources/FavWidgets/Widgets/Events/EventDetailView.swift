import SwiftUI
import PhotosUI
import FavWidgetsCore

/// One event: the shared album, the places, the people. Members only.
struct EventDetailView: View {
    let context: WidgetContext
    let eventId: String
    /// A one-off celebration line ("You're in Party Bus! +1 FavCoin")
    let banner: String?
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
    @State private var showBanner = false
    @State private var confirmEnd = false
    @State private var confirmLeave = false
    @State private var showRecap = false
    @State private var showAddChallenges = false
    /// A photo being added for this challenge (camera or library)
    @State private var challengeForPhoto: EventChallenge?
    @State private var askChallengeSource = false
    @State private var showChallengeLibrary = false
    @State private var challengeItems: [PhotosPickerItem] = []
    @State private var pendingChallengeId: String?
    @State private var toast: String?
    @State private var onLockScreen = false
    @State private var showMap = false
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case photos = "Photos", wall = "Wall", songs = "Songs", places = "Places", people = "People" }

    init(context: WidgetContext, eventId: String, banner: String? = nil, onGone: @escaping () -> Void, onChange: @escaping (EventSummary) -> Void) {
        self.context = context
        self.eventId = eventId
        self.banner = banner
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
                        if event.isArchived {
                            Label(event.isArchivedForEveryone ? "Archived by the coordinator. Photos are still here." : "Archived for you. Photos are still here.",
                                  systemImage: "archivebox")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.secondaryLabel)
                        }
                        EventNotificationNudge(context: context, event: event)
                        header(event, theme: theme)
                        if event.hasEnded { recapCard(event, theme: theme) }
                        if let rollCall = event.rollCall {
                            EventRollCallBanner(context: context, event: event, rollCall: rollCall) { updated in
                                if let updated { model.replaceEvent(updated) } else { Task { await model.load() } }
                            }
                        }
                        actions(event, theme: theme)
                        Picker("Section", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch tab {
                        case .photos:
                            if !event.challengeList.isEmpty || (event.isHost && !event.hasEnded) {
                                EventChallengesStrip(context: context, event: event, photos: model.photos,
                                                     onPick: { challengeForPhoto = $0; askChallengeSource = true },
                                                     onAdd: { showAddChallenges = true })
                            }
                            photosSection(event, theme: theme)
                        case .wall: EventWallSection(context: context, event: event)
                        case .songs: EventSongsSection(context: context, event: event)
                        case .places: EventPlacesSection(context: context, model: model, event: event, onShowMap: { showMap = true })
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
            .overlay(alignment: .top) {
                if showBanner, let banner {
                    Text("🎉 \(banner)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(context.accent))
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(Color.green))
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
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
        .task {
            guard banner != nil else { return }
            withAnimation(.spring()) { showBanner = true }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { showBanner = false }
        }
        .onChange(of: model.detail?.event) { event in if let event { onChange(event) } }
        .onChange(of: pickedItems) { items in
            guard !items.isEmpty else { return }
            pickedItems = []
            Task { await uploadPicked(items) }
        }
        .onChange(of: cameraImage) { image in
            guard let image else { return }
            cameraImage = nil
            let challenge = pendingChallengeId
            pendingChallengeId = nil
            Task { await upload(images: [image], challengeId: challenge) }
        }
        .onChange(of: challengeItems) { items in
            guard !items.isEmpty else { return }
            challengeItems = []
            let challenge = pendingChallengeId
            pendingChallengeId = nil
            Task { await uploadPicked(items, challengeId: challenge) }
        }
        .photosPicker(isPresented: $showChallengeLibrary, selection: $challengeItems, maxSelectionCount: 5, matching: .images)
        .confirmationDialog(challengeForPhoto.map { "\($0.emoji) \($0.text)" } ?? "", isPresented: $askChallengeSource, titleVisibility: .visible) {
            #if os(iOS)
            if PostcardCameraPicker.isAvailable {
                Button("Take a photo") { pendingChallengeId = challengeForPhoto?.id; showCamera = true }
            }
            #endif
            Button("Choose from library") { pendingChallengeId = challengeForPhoto?.id; showChallengeLibrary = true }
        }
        .sheet(isPresented: $showRecap) { EventRecapView(context: context, eventId: eventId) }
        .sheet(isPresented: $showMap) {
            if let event = model.detail?.event {
                EventMapSheet(context: context, model: model, event: event) { circleId in openCircle(circleId) }
            }
        }
        .sheet(isPresented: $showAddChallenges) {
            if let event = model.detail?.event {
                EventAddChallengesSheet(context: context, event: event) { _ in Task { await model.load() } }
            }
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
            if let event = model.detail?.event {
                EventInviteSheet(context: context, event: event) { model.replaceEvent($0) }
            }
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
                    Text("\(event.hasEnded ? "Ended · " : "")\(EventCopy.memberCount(event.members.count)) · run by \(event.isHost ? "you" : event.hostName)")
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
            // Every place the group tagged, on a map (Wes, 2026-10-07)
            Button { showMap = true; context.track("event_map_opened") } label: { actionLabel("Map", "map.fill", theme: theme) }
                .buttonStyle(.plain)
            if !event.hasEnded {
                Button { toggleLockScreen(event) } label: {
                    actionLabel(onLockScreen ? "On Lock Screen" : "Lock Screen", onLockScreen ? "checkmark.circle.fill" : "iphone.gen3", theme: theme)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { onLockScreen = context.host.isEventLiveActivityOn(eventId: event.id) }
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
                if !event.hasEnded {
                    if event.rollCall == nil {
                        Button { startRollCall() } label: { Label("Roll call", systemImage: "hand.raised") }
                    }
                    Button { showAddChallenges = true } label: { Label("Photo challenges", systemImage: "camera.badge.ellipsis") }
                }
            }
            if event.hasEnded {
                Button { showRecap = true } label: { Label("Recap", systemImage: "sparkles") }
            }
            if !model.photos.isEmpty {
                Button { Task { await downloadAll() } } label: { Label("Download all photos", systemImage: "square.and.arrow.down.on.square") }
            }
            Divider()
            if event.isArchived {
                Button { unarchive() } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
            } else {
                Button { archive(forEveryone: false) } label: { Label("Archive for me", systemImage: "archivebox") }
                if event.isHost {
                    Button { archive(forEveryone: true) } label: { Label("Archive for everyone", systemImage: "archivebox.fill") }
                }
            }
            if event.isHost {
                Button(role: .destructive) { confirmEnd = true } label: { Label("End event (deletes the album)", systemImage: "trash") }
            } else {
                Button(role: .destructive) { confirmLeave = true } label: { Label("Leave \(event.name)", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .confirmationDialog("End \(event.name)?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End event", role: .destructive) { end() }
        } message: {
            Text("The album and places are removed for everyone. Circles people saved stay theirs. To just put it away, use Archive.")
        }
        .confirmationDialog("Leave \(event.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leave() }
        } message: {
            Text("You'll lose access to the album. To just put it away, use Archive for me.")
        }
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
                                CachedRemoteImage(url: URL(string: photo.gridURL)) { image in
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

    private func uploadPicked(_ items: [PhotosPickerItem], challengeId: String? = nil) async {
        var images: [PostcardPlatformImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data) {
                images.append(image)
            }
        }
        await upload(images: images, challengeId: challengeId)
    }

    private func upload(images: [PostcardPlatformImage], challengeId: String? = nil) async {
        guard !images.isEmpty else { return }
        var urls: [(full: URL, thumb: URL?)] = []
        for (i, image) in images.enumerated() {
            model.uploading = EventCopy.uploadProgress(done: i, total: images.count)
            guard let full = EventImagePrep.jpeg(image) else { continue }
            guard let fullURL = try? await context.host.uploadImage(full) else { continue }
            // The grid's ~25 KB preview; a failed preview just means the grid loads the photo
            let thumbURL: URL? = if let thumb = EventImagePrep.thumbnail(image) { try? await context.host.uploadImage(thumb) } else { nil }
            urls.append((fullURL, thumbURL))
        }
        defer { model.uploading = nil }
        guard !urls.isEmpty else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't add photos", message: "Check your connection and try again."))
            return
        }
        do {
            let added = try await EventsClient(context: context).addPhotos(eventId, urls: urls, challengeId: challengeId)
            model.prependPhotos(added)
            tab = .photos
            context.host.haptic(.success)
            if challengeId != nil { celebrate("Challenge done! 🎉") }
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

    private func archive(forEveryone: Bool) {
        Task { @MainActor in
            do {
                let updated = try await EventsClient(context: context).archive(eventId, forEveryone: forEveryone)
                model.replaceEvent(updated)
                context.host.haptic(.success)
                context.track("event_archived", ["everyone": forEveryone ? "1" : "0"])
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't archive", message: "Check your connection and try again."))
            }
        }
    }

    private func unarchive() {
        Task { @MainActor in
            if let updated = try? await EventsClient(context: context).unarchive(eventId) {
                model.replaceEvent(updated)
                context.host.haptic(.success)
            }
        }
    }

    private func end() {
        Task { @MainActor in
            if (try? await EventsClient(context: context).end(eventId)) != nil { dismiss(); onGone() }
        }
    }

    private func leave() {
        Task { @MainActor in
            if (try? await EventsClient(context: context).leave(eventId)) != nil { dismiss(); onGone() }
        }
    }

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

    private func celebrate(_ text: String) {
        withAnimation(.spring()) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toast = nil }
        }
    }

    /// The event on this phone's lock screen and Dynamic Island, updated by
    /// the server as photos, shout-outs, songs and roll call happen.
    private func toggleLockScreen(_ event: EventSummary) {
        Task { @MainActor in
            if onLockScreen {
                await context.host.stopEventLiveActivity(eventId: event.id)
                onLockScreen = false
                return
            }
            let ok = await context.host.startEventLiveActivity(WidgetEventLiveStart(
                eventId: event.id, name: event.name, emoji: event.emoji, members: event.members.count, photos: event.photoCount))
            onLockScreen = ok
            if ok {
                context.host.haptic(.success)
                context.track("event_lock_screen_on")
                celebrate("On your Lock Screen 🔒")
            } else {
                context.host.presentAlert(WidgetAlert(title: "Live Activities are off",
                                                      message: "Turn on Live Activities for FavCircles in Settings to keep the event on your Lock Screen."))
            }
        }
    }

    /// The event circle on the profile: close the event, then open it there.
    private func openCircle(_ circleId: String) {
        showMap = false
        context.track("event_circle_opened")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            dismiss()
            try? await Task.sleep(nanoseconds: 450_000_000)
            if let url = URL(string: "circles://circle/\(circleId)") { context.host.openURL(url) }
        }
    }

    private func startRollCall() {
        Task { @MainActor in
            if let updated = try? await EventsClient(context: context).startRollCall(eventId) {
                model.replaceEvent(updated)
                context.host.haptic(.success)
                context.track("event_rollcall_started")
            }
        }
    }

    private func recapCard(_ event: EventSummary, theme: WidgetTheme) -> some View {
        Button { showRecap = true } label: {
            HStack(spacing: 12) {
                Text("✨").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(event.name) has ended").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.label)
                    Text("See the recap: photo of the night, the stops, the song of the night")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        }
        .buttonStyle(.plain)
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
                CachedRemoteImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initial }
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
    /// The photo: 1920 px at 0.72 lands under the upload's 750 KB target in
    /// one pass (2048 px at 0.85 was always re-compressed by the uploader).
    static func jpeg(_ image: PostcardPlatformImage) -> Data? { encode(image, longest: 1920, quality: 0.72) }

    /// The album grid's preview: 400 px (a grid square is ~435 px on the
    /// biggest phones), ~25–35 KB for a real phone photo.
    static func thumbnail(_ image: PostcardPlatformImage) -> Data? { encode(image, longest: 400, quality: 0.6) }

    private static func encode(_ image: PostcardPlatformImage, longest maxSide: CGFloat, quality: CGFloat) -> Data? {
        #if os(iOS)
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longest, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
        #else
        return nil
        #endif
    }
}

import SwiftUI
import AVKit
import FavWidgetsCore

/// Full-screen swipe through the album: like, save to Photos, share, delete.
struct EventPhotoViewer: View {
    let context: WidgetContext
    @ObservedObject var model: EventDetailModel
    let startId: String
    @State private var currentId: String = ""
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if model.photos.isEmpty {
                    Text("No photos").foregroundStyle(.white)
                } else {
                    TabView(selection: $currentId) {
                        ForEach(model.photos) { photo in
                            if photo.isVideo, let url = URL(string: photo.videoUrl ?? "") {
                                EventVideoPage(url: url, isCurrent: currentId == photo.id)
                                    .tag(photo.id)
                            } else {
                                // Pinch or double-tap to zoom; the cached grid
                                // preview shows while the full photo loads
                                ZoomableRemoteImage(url: URL(string: photo.imageUrl), previewURL: URL(string: photo.gridURL),
                                                    isCurrent: currentId == photo.id)
                                    .tag(photo.id)
                            }
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    #endif
                }
            }
            .safeAreaInset(edge: .bottom) { if let photo = current { bar(photo) } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(.white) } }
        }
        .onAppear { currentId = startId }
    }

    private var current: EventPhoto? { model.photos.first { $0.id == currentId } }

    private func bar(_ photo: EventPhoto) -> some View {
        VStack(spacing: 10) {
            Text("by \(photo.uploaderName)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 28) {
                Button { like(photo) } label: {
                    Label("\(photo.likeCount)", systemImage: photo.likedByMe ? "heart.fill" : "heart")
                        .foregroundStyle(photo.likedByMe ? .pink : .white)
                }
                Button { Task { await save(photo) } } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel(photo.isVideo ? "Save video to Photos" : "Save photo to Photos")
                Button { Task { await share(photo) } } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(photo.isVideo ? "Share video" : "Share photo")
                if photo.canDelete {
                    Button(role: .destructive) { delete(photo) } label: { Image(systemName: "trash") }
                }
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .disabled(busy)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.6))
    }

    private func like(_ photo: EventPhoto) {
        context.host.haptic(.light)
        Task { @MainActor in
            if let updated = try? await EventsClient(context: context).like(model.eventId, photo: photo.id) { model.replacePhoto(updated) }
        }
    }

    private func imageData(_ photo: EventPhoto) async -> Data? {
        guard let url = URL(string: photo.imageUrl), let fetched = try? await URLSession.shared.data(from: url) else { return nil }
        return fetched.0
    }

    private func save(_ photo: EventPhoto) async {
        busy = true
        defer { busy = false }
        if photo.isVideo {
            guard let file = await EventMediaDownload.video(photo) else { return downloadFailed() }
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                try await context.host.saveVideoToPhotos(file)
                context.host.haptic(.success)
                context.track("event_video_saved")
                context.host.presentAlert(WidgetAlert(title: "Saved", message: "The video is in your Photos."))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save to Photos", message: "Allow FavCircles to add photos in Settings, then try again."))
            }
            return
        }
        guard let data = await imageData(photo) else { return downloadFailed() }
        do {
            try await context.host.saveImageToPhotos(data)
            context.host.haptic(.success)
            context.track("event_photo_saved")
            context.host.presentAlert(WidgetAlert(title: "Saved", message: "The photo is in your Photos."))
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't save to Photos", message: "Allow FavCircles to add photos in Settings, then try again."))
        }
    }

    /// Shares the file itself, never its link: the link would work for
    /// anyone, and event media is members-only.
    private func share(_ photo: EventPhoto) async {
        busy = true
        defer { busy = false }
        if photo.isVideo {
            // The file stays in tmp while the share sheet may still read it
            guard let file = await EventMediaDownload.video(photo) else { return downloadFailed() }
            context.track("event_video_shared")
            context.host.share([.file(file)])
            return
        }
        guard let data = await imageData(photo) else { return downloadFailed() }
        context.host.share([.imageJPEG(data)])
    }

    private func downloadFailed() {
        context.host.presentAlert(WidgetAlert(title: "Couldn't download it", message: "Check your connection and try again."))
    }

    private func delete(_ photo: EventPhoto) {
        Task { @MainActor in
            do {
                try await EventsClient(context: context).deletePhoto(model.eventId, photo: photo.id)
                let next = model.photos.firstIndex(where: { $0.id == photo.id }).flatMap { i in
                    model.photos.indices.contains(i + 1) ? model.photos[i + 1].id : (i > 0 ? model.photos[i - 1].id : nil)
                }
                model.removePhoto(photo.id)
                if let next { currentId = next } else { dismiss() }
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't delete", message: "Check your connection and try again."))
            }
        }
    }
}

/// One clip in the album viewer: plays while it's the page on screen.
struct EventVideoPage: View {
    let url: URL
    let isCurrent: Bool
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear { sync() }
        .onChange(of: isCurrent) { _ in sync() }
        .onDisappear { player?.pause() }
    }

    private func sync() {
        if isCurrent {
            if player == nil { player = AVPlayer(url: url) }
            player?.play()
        } else {
            player?.pause()
        }
    }
}

/// Event media downloaded to a temporary file.
enum EventMediaDownload {
    /// The clip as a local .mp4, or nil when it can't be downloaded.
    static func video(_ photo: EventPhoto) async -> URL? {
        guard photo.isVideo, let remote = URL(string: photo.videoUrl ?? ""),
              let (downloaded, response) = try? await URLSession.shared.download(from: remote),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let name = "\(photo.uploaderName.replacingOccurrences(of: "/", with: "-")) \(photo.id.prefix(6)).mp4"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)
        do { try FileManager.default.moveItem(at: downloaded, to: file) } catch { return nil }
        return file
    }
}

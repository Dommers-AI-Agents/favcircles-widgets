import SwiftUI
import MapKit
import FavWidgetsCore

/// The after-party recap: who came, the photo of the night, the top
/// photographer, the stops on a map, the most-voted song and the shout-out
/// everyone loved. Shareable as one image.
struct EventRecapView: View {
    let context: WidgetContext
    let eventId: String
    @State private var recap: EventRecap?
    @State private var failed = false
    @State private var sharing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                if let recap {
                    VStack(alignment: .leading, spacing: 18) {
                        EventRecapCard(recap: recap, images: [:], accent: context.accent, live: true)
                        if !recap.places.isEmpty {
                            WidgetUI.header("Where you went", theme: theme)
                            EventRecapMap(spots: recap.places)
                                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                            ForEach(recap.places, id: \.self) { spot in
                                Label(spot.name, systemImage: "mappin.circle.fill").font(.system(size: 15)).foregroundStyle(theme.label)
                            }
                        }
                        if recap.topPhotos.count > 1 {
                            WidgetUI.header("Favorite photos", theme: theme)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                                ForEach(recap.topPhotos, id: \.self) { p in
                                    Color.gray.opacity(0.15).aspectRatio(1, contentMode: .fit)
                                        .overlay(CachedRemoteImage(url: URL(string: p.gridURL)) { $0.resizable().scaledToFill() } placeholder: { ProgressView() })
                                        .clipped()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Text("With " + recap.memberNames.joined(separator: ", "))
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        WidgetUI.primaryButton(sharing ? "Making the image…" : "Share recap", color: context.accent) { share(recap) }
                            .disabled(sharing)
                    }
                    .padding(16)
                } else if failed {
                    Text("Couldn't load the recap. Pull to try again.").foregroundStyle(theme.secondaryLabel).padding(.top, 60).frame(maxWidth: .infinity)
                } else {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                }
            }
            .refreshable { await load() }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Recap")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task { await load() }
    }

    private func load() async {
        do { recap = try await EventsClient(context: context).recap(eventId); failed = false } catch { failed = true }
    }

    /// Downloads the photos the card shows, then renders it as a JPEG.
    @MainActor
    private func share(_ recap: EventRecap) {
        sharing = true
        Task { @MainActor in
            defer { sharing = false }
            var images: [String: PostcardPlatformImage] = [:]
            let urls = ([recap.photoOfTheNight?.imageUrl] + recap.topPhotos.prefix(3).map(\.imageUrl)).compactMap { $0 }
            for u in Set(urls) {
                if let url = URL(string: u), let image = await RemoteImageCache.image(for: url) { images[u] = image }
            }
            let card = EventRecapCard(recap: recap, images: images, accent: context.accent, live: false)
                .frame(width: 390).padding(20).background(Color.black)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            #if os(iOS)
            guard let image = renderer.uiImage, let jpeg = image.jpegData(compressionQuality: 0.88) else { return }
            #else
            guard let cg = renderer.cgImage, let jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [:]) else { return }
            #endif
            context.track("event_recap_shared")
            context.host.share([.imageJPEG(jpeg), .text("\(recap.emoji) \(recap.name) — recap from FavCircles")])
        }
    }
}

/// The recap's headline card. `live` uses AsyncImage on screen; the shared
/// image is rendered from already-downloaded `images` (ImageRenderer can't
/// wait for a download).
struct EventRecapCard: View {
    let recap: EventRecap
    let images: [String: PostcardPlatformImage]
    let accent: Color
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(recap.emoji).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recap.name).font(.system(size: 24, weight: .heavy, design: .rounded))
                    if let when = dateLine { Text(when).font(.system(size: 13)).opacity(0.85) }
                }
            }
            HStack(spacing: 0) {
                stat("\(recap.memberCount)", "people")
                stat("\(recap.photoCount)", "photos")
                stat("\(recap.placeCount)", "stops")
                if recap.challenges.total > 0 { stat("\(recap.challenges.done)/\(recap.challenges.total)", "challenges") }
            }
            if let best = recap.photoOfTheNight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("📸 Photo of the night").font(.system(size: 14, weight: .bold))
                    photo(best.imageUrl).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("by \(best.uploaderName) · ♥ \(best.likes)").font(.system(size: 13)).opacity(0.85)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let p = recap.topPhotographer { line("🏆", "Top photographer: \(p.name) (\(p.photos))") }
                if let s = recap.topSong { line("🎵", "Song of the night: \(s.title)\(s.artist.map { " · \($0)" } ?? "")") }
                if let s = recap.topShoutout { line("💬", "\u{201C}\(s.text)\u{201D} — \(s.authorName)") }
            }
            Text("FavCircles").font(.system(size: 12, weight: .bold)).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.24, blue: 0.5), accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var dateLine: String? {
        guard let start = recap.startedAt.flatMap(EventTimes.date) else { return nil }
        return start.formatted(date: .abbreviated, time: .omitted)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(label).font(.system(size: 11)).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private func line(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) { Text(emoji); Text(text).fixedSize(horizontal: false, vertical: true) }
            .font(.system(size: 14, weight: .semibold))
    }

    @ViewBuilder
    private func photo(_ url: String) -> some View {
        if let image = images[url] {
            Image(postcardImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
        } else if live {
            Color.white.opacity(0.15).overlay(CachedRemoteImage(url: URL(string: url)) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }).clipped()
        } else {
            Color.white.opacity(0.15)
        }
    }
}

/// The stops as pins.
struct EventRecapMap: View {
    let spots: [EventRecap.Spot]

    var body: some View {
        let region = Self.region(spots)
        Map(coordinateRegion: .constant(region), annotationItems: spots.indices.map { IndexedSpot(i: $0, spot: spots[$0]) }) { item in
            MapMarker(coordinate: CLLocationCoordinate2D(latitude: item.spot.lat, longitude: item.spot.lng), tint: .pink)
        }
        .allowsHitTesting(false)
    }

    private struct IndexedSpot: Identifiable { let i: Int; let spot: EventRecap.Spot; var id: Int { i } }

    static func region(_ spots: [EventRecap.Spot]) -> MKCoordinateRegion {
        let lats = spots.map(\.lat), lngs = spots.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.2, longitude: -80.8), span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.5), longitudeDelta: max(0.01, (maxLng - minLng) * 1.5)))
    }
}

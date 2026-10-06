import SwiftUI
import FavWidgetsCore

/// `AsyncImage` that keeps what it loaded: one shared URL cache on disk, so
/// reopening an album costs nothing. Firebase Storage download URLs carry a
/// token and never change in place, so a cached copy never goes stale.
/// (2026-10-06: an event album re-downloaded every full photo on each open.)
struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: PostcardPlatformImage?

    var body: some View {
        Group {
            if let image { content(Image(postcardImage: image)) } else { placeholder() }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await RemoteImageCache.image(for: url)
        }
    }
}

enum RemoteImageCache {
    /// 64 MB in memory, 512 MB on disk (a few events' albums).
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                                       .appendingPathComponent("FavWidgetsImages"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    static func image(for url: URL) async -> PostcardPlatformImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return PostcardPlatformImage(data: data)
    }
}

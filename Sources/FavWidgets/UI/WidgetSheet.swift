import SwiftUI
import FavWidgetsCore

/// The sheet scaffold every widget was re-typing: a navigation stack, an
/// inline title, Cancel on the left and an optional confirm on the right.
struct WidgetSheet<Content: View>: View {
    let title: String
    let theme: WidgetTheme
    var confirm: (label: String, enabled: Bool, action: () -> Void)?
    var cancelDisabled = false
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .background(theme.background.ignoresSafeArea())
                .widgetInlineNavigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(cancelDisabled)
                    }
                    if let confirm {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(confirm.label, action: confirm.action).disabled(!confirm.enabled)
                        }
                    }
                }
        }
    }
}

/// Serializes a screen's async actions: one in flight at a time, with the
/// key of the busy one so its button can show a spinner while the rest
/// stay tappable-but-refused.
@MainActor
final class BusyRunner: ObservableObject {
    @Published private(set) var busy: String?

    var isBusy: Bool { busy != nil }

    /// Runs `op` unless something else is in flight; errors go to `onError`.
    func run(_ key: String, onError: @escaping (Error) -> Void, _ op: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = key
        Task {
            defer { busy = nil }
            do { try await op() } catch { onError(error) }
        }
    }
}

extension WidgetUI {
    /// The plain text field the address and note forms share: one height,
    /// one radius, no autocorrect.
    static func textField(_ placeholder: String, text: Binding<String>, theme: WidgetTheme,
                          fill: Color? = nil, content: WidgetTextContent? = nil, numeric: Bool = false,
                          capitalizeAll: Bool = false, height: CGFloat = 38) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15))
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill ?? theme.secondaryBackground))
            #if os(iOS)
            .textContentType(content?.uiContentType)
            .keyboardType(numeric ? .numbersAndPunctuation : .default)
            .textInputAutocapitalization(capitalizeAll ? .characters : .words)
            #endif
    }

    /// A small remote image on a soft background with a symbol fallback.
    /// Decodes at thumbnail size, so a print-resolution JPEG never becomes a
    /// full bitmap behind a 60-point box.
    static func thumbnail(url: URL?, width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 6,
                          background: Color, fallbackSymbol: String? = nil, fallbackColor: Color = .secondary,
                          contentMode: ContentMode = .fit) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(background)
            if let url {
                WidgetThumbnailImage(url: url, targetPixels: max(width, height) * 3, contentMode: contentMode,
                                     fallbackSymbol: fallbackSymbol, fallbackColor: fallbackColor)
            } else if let fallbackSymbol {
                Image(systemName: fallbackSymbol).font(.system(size: min(width, height) * 0.42, weight: .semibold)).foregroundStyle(fallbackColor)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Loads a URL and decodes it down-sampled to `targetPixels` on the long
/// edge (CGImageSource thumbnailing), caching the result per URL for the
/// process. AsyncImage would decode the full image every time.
struct WidgetThumbnailImage: View {
    let url: URL
    let targetPixels: CGFloat
    let contentMode: ContentMode
    let fallbackSymbol: String?
    let fallbackColor: Color
    @State private var image: PostcardPlatformImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(postcardImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed, let fallbackSymbol {
                Image(systemName: fallbackSymbol).foregroundStyle(fallbackColor)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            if let cached = WidgetThumbnailCache.shared.image(for: url, pixels: targetPixels) { image = cached; return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let decoded = WidgetThumbnailCache.decode(data, targetPixels: targetPixels) {
                    WidgetThumbnailCache.shared.store(decoded, for: url, pixels: targetPixels)
                    image = decoded
                } else { failed = true }
            } catch { failed = true }
        }
    }
}

final class WidgetThumbnailCache {
    static let shared = WidgetThumbnailCache()
    private let cache = NSCache<NSString, PostcardPlatformImage>()

    private init() { cache.countLimit = 300 }

    private func key(_ url: URL, _ pixels: CGFloat) -> NSString { "\(Int(pixels))|\(url.absoluteString)" as NSString }
    func image(for url: URL, pixels: CGFloat) -> PostcardPlatformImage? { cache.object(forKey: key(url, pixels)) }
    func store(_ image: PostcardPlatformImage, for url: URL, pixels: CGFloat) { cache.setObject(image, forKey: key(url, pixels)) }

    static func decode(_ data: Data, targetPixels: CGFloat) -> PostcardPlatformImage? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(targetPixels),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
        #else
        return nil
        #endif
    }
}

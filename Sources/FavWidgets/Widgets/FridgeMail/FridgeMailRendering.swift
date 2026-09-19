import SwiftUI
import FavWidgetsCore

/// The printed front of a Fridge Mail card: the drawing, whole, on a warm
/// frame with the child's name underneath. Drawn identically for the
/// on-screen preview and the print JPEG; every metric scales with `size`.
struct FridgeMailCanvasView: View {
    let image: PostcardPlatformImage?
    let childName: String
    let size: CGSize
    /// Bleed the trimmer cuts away (print only); content stays inside it.
    var bleed: CGFloat = 0

    static let cream = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let frame = Color(red: 0.93, green: 0.62, blue: 0.22)
    static let ink = Color(red: 0.36, green: 0.22, blue: 0.10)

    /// 1.0 at the 600pt design width.
    private var scale: CGFloat { max(0.2, size.width / 600) }

    var body: some View {
        let inset = 26 * scale + bleed
        let strip: CGFloat = childName.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 44 * scale
        let imageSize = image.map { CGSize(width: $0.size.width, height: $0.size.height) } ?? CGSize(width: 3, height: 2)
        let rect = FridgeMailLayout.fit(image: imageSize, canvas: size, inset: inset, stripHeight: strip)
        ZStack(alignment: .topLeading) {
            Self.cream
            // A thin painted border just inside the trim, so the card reads
            // as a frame around the art rather than a photo print.
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .stroke(Self.frame, lineWidth: 3 * scale)
                .padding(bleed + 10 * scale)
            Group {
                if let image {
                    Image(postcardImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 4 * scale).fill(Self.frame.opacity(0.18))
                }
            }
            .frame(width: rect.width, height: rect.height)
            .background(Color.white)
            .shadow(color: .black.opacity(0.12), radius: 4 * scale, x: 0, y: 2 * scale)
            .offset(x: rect.minX, y: rect.minY)
            if strip > 0 {
                Text(childName)
                    .font(.system(size: 24 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: size.width - inset * 2, height: strip)
                    .offset(x: inset, y: size.height - inset - strip)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Renders the canvas to the JPEG the print pipeline expects: the same
/// 1875x1275 full-bleed geometry as a mailed postcard, so the server's
/// validator and Lob's 4x6 template accept it unchanged.
@MainActor
enum FridgeMailRendering {
    static func printJPEG(image: PostcardPlatformImage, childName: String) throws -> Data {
        let canvas = FridgeMailCanvasView(
            image: image,
            childName: childName,
            size: PostcardRendering.printRenderSize,
            bleed: PostcardRendering.printBleed
        )
        #if os(iOS)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = PostcardRendering.printScale
        renderer.proposedSize = ProposedViewSize(PostcardRendering.printRenderSize)
        guard let rendered = renderer.uiImage, let data = rendered.jpegData(compressionQuality: PostcardRendering.printJPEGQuality) else {
            throw PostcardRenderError.renderFailed
        }
        return data
        #else
        _ = canvas
        throw PostcardRenderError.unsupportedPlatform
        #endif
    }
}

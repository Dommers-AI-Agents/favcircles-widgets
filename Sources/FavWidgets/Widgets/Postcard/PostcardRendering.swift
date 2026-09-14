import SwiftUI

enum PostcardRenderError: LocalizedError {
    case unsupportedPlatform
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform: return "Postcards can only be rendered on iPhone or iPad."
        case .renderFailed: return "The postcard image couldn't be created."
        }
    }
}

/// Turns the canvas into the JPEG the host uploads.
///
/// Two outputs from one canvas. The screen/share/email card is a light
/// 1200x800; a card we hand to a printer has to be 300 DPI with bleed, which
/// is a different size, a different quality, and a safe margin the digital
/// card doesn't need.
@MainActor
enum PostcardRendering {
    /// 6x4 postcard at 2x → a 1200x800 JPEG.
    static let renderSize = CGSize(width: 600, height: 400)
    static let scale: CGFloat = 2
    static let jpegQuality: CGFloat = 0.85

    // MARK: Print

    /// 6.25in x 4.25in at 100pt/in: the 6x4 finished card plus 0.125in of
    /// bleed on every side, which the trimmer cuts away.
    static let printRenderSize = CGSize(width: 625, height: 425)
    /// 3x of the above is 1875x1275 — 300 DPI across the bleed size.
    static let printScale: CGFloat = 3
    /// Print is unforgiving about JPEG artifacts in flat areas (skies, the
    /// white border), so this runs much higher than the screen card. Costs
    /// roughly 700KB-1.5MB versus ~150KB.
    static let printJPEGQuality: CGFloat = 0.95
    /// The bleed itself, in render points: 0.125in at 100pt/in.
    static let printBleed: CGFloat = 12.5

    static func jpeg(image: PostcardPlatformImage, templateId: String, caption: String, accent: Color) throws -> Data {
        let canvas = PostcardCanvasView(image: image, templateId: templateId, caption: caption, size: renderSize, accent: accent)
        return try render(canvas, size: renderSize, scale: scale, quality: jpegQuality)
    }

    /// The print-resolution JPEG: 1875x1275, full bleed, content held inside
    /// the trim. Only for cards that are actually going to be printed.
    static func printJPEG(image: PostcardPlatformImage, templateId: String, caption: String, accent: Color) throws -> Data {
        let canvas = PostcardCanvasView(
            image: image,
            templateId: templateId,
            caption: caption,
            size: printRenderSize,
            accent: accent,
            bleed: printBleed
        )
        return try render(canvas, size: printRenderSize, scale: printScale, quality: printJPEGQuality)
    }

    /// Long-edge pixels below which a source photo will look soft at 6x4.
    /// Warn, never block — the user may well not care.
    static let minimumSourceLongEdge: CGFloat = 1200

    static func isSoftForPrint(_ image: PostcardPlatformImage) -> Bool {
        #if os(iOS)
        let pixels = max(image.size.width, image.size.height) * image.scale
        return pixels < minimumSourceLongEdge
        #else
        return false
        #endif
    }

    // MARK: - Shared

    private static func render(_ canvas: PostcardCanvasView, size: CGSize, scale: CGFloat, quality: CGFloat) throws -> Data {
        #if os(iOS)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let rendered = renderer.uiImage, let data = rendered.jpegData(compressionQuality: quality) else {
            throw PostcardRenderError.renderFailed
        }
        return data
        #else
        _ = canvas
        throw PostcardRenderError.unsupportedPlatform
        #endif
    }
}

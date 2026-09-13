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
@MainActor
enum PostcardRendering {
    /// 6x4 postcard at 2x → a 1200x800 JPEG.
    static let renderSize = CGSize(width: 600, height: 400)
    static let scale: CGFloat = 2
    static let jpegQuality: CGFloat = 0.85

    static func jpeg(image: PostcardPlatformImage, templateId: String, caption: String, accent: Color) throws -> Data {
        let canvas = PostcardCanvasView(image: image, templateId: templateId, caption: caption, size: renderSize, accent: accent)
        #if os(iOS)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(renderSize)
        guard let rendered = renderer.uiImage, let data = rendered.jpegData(compressionQuality: jpegQuality) else {
            throw PostcardRenderError.renderFailed
        }
        return data
        #else
        _ = canvas
        throw PostcardRenderError.unsupportedPlatform
        #endif
    }
}

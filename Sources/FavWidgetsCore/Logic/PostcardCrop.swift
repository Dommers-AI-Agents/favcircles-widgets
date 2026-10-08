import Foundation
import CoreGraphics

/// Where the photo sits in the postcard's photo window (Wes, 2026-10-08: the
/// top of a photo was cut off with no way to fix it). The photo always fills
/// the window; `zoom` enlarges it past that, and `x`/`y` (−1…1) slide it
/// across whatever spills over the edges — so no position can leave a gap.
/// Resolution-independent: the same crop places the photo identically on the
/// preview, the thumbnails, the digital card and the 300 DPI print.
public struct PostcardCrop: Codable, Equatable, Sendable {
    public var zoom: Double
    public var x: Double
    public var y: Double

    public init(zoom: Double = 1, x: Double = 0, y: Double = 0) {
        self.zoom = min(max(zoom, 1), PostcardCrop.maxZoom)
        self.x = min(max(x, -1), 1)
        self.y = min(max(y, -1), 1)
    }

    public static let maxZoom: Double = 4
    public static let centered = PostcardCrop()
    /// No faces found: a little more of the top than dead center, where
    /// heads, skylines and signs usually are
    public static let topBiased = PostcardCrop(y: 0.3)

    /// The photo's drawn size and its offset from the window's center.
    public func layout(image: CGSize, frame: CGSize) -> (size: CGSize, offset: CGSize) {
        guard image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else { return (frame, .zero) }
        let fill = max(frame.width / image.width, frame.height / image.height) * zoom
        let size = CGSize(width: image.width * fill, height: image.height * fill)
        let spare = CGSize(width: (size.width - frame.width) / 2, height: (size.height - frame.height) / 2)
        return (size, CGSize(width: x * spare.width, height: y * spare.height))
    }

    /// Dragged by (dx, dy) points in a window of `frame`.
    public func panned(dx: Double, dy: Double, image: CGSize, frame: CGSize) -> PostcardCrop {
        let spare = Self.spare(image: image, frame: frame, zoom: zoom)
        return PostcardCrop(zoom: zoom,
                            x: spare.width > 0 ? x + dx / spare.width : 0,
                            y: spare.height > 0 ? y + dy / spare.height : 0)
    }

    /// Pinched to `zoom`, keeping the same point in the middle of the window.
    public func zoomed(to newZoom: Double, image: CGSize, frame: CGSize) -> PostcardCrop {
        let before = Self.spare(image: image, frame: frame, zoom: zoom)
        let target = min(max(newZoom, 1), Self.maxZoom)
        let after = Self.spare(image: image, frame: frame, zoom: target)
        let ox = x * before.width, oy = y * before.height
        let nx = after.width > 0 ? (ox * target / zoom) / after.width : 0
        let ny = after.height > 0 ? (oy * target / zoom) / after.height : 0
        return PostcardCrop(zoom: target, x: nx, y: ny)
    }

    /// Centers the window on `subject` — a rect in unit image coordinates
    /// (0…1, top-left origin), e.g. the faces in the photo.
    public static func centering(on subject: CGRect, image: CGSize, frame: CGSize) -> PostcardCrop {
        let base = PostcardCrop()
        let (size, _) = base.layout(image: image, frame: frame)
        let spare = spare(image: image, frame: frame, zoom: 1)
        let ox = -(subject.midX - 0.5) * size.width
        let oy = -(subject.midY - 0.5) * size.height
        return PostcardCrop(zoom: 1, x: spare.width > 0 ? ox / spare.width : 0, y: spare.height > 0 ? oy / spare.height : 0)
    }

    static func spare(image: CGSize, frame: CGSize, zoom: Double) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let fill = max(frame.width / image.width, frame.height / image.height) * zoom
        return CGSize(width: max(0, (image.width * fill - frame.width) / 2), height: max(0, (image.height * fill - frame.height) / 2))
    }
}

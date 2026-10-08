import SwiftUI
import FavWidgetsCore
#if canImport(Vision) && os(iOS)
import Vision
#endif

/// Where a new photo starts on the card: centered on the people in it when
/// there are faces, a little above center otherwise (where heads, skylines
/// and signs usually are) — rather than dead center, which cut off the top.
enum PostcardPhotoFraming {
    /// The postcard's photo window, near enough for every template
    static let window = CGSize(width: 600, height: 400)

    static func initialCrop(for image: PostcardPlatformImage) -> PostcardCrop {
        #if canImport(Vision) && os(iOS)
        if let faces = faces(in: image) {
            return PostcardCrop.centering(on: faces, image: image.size, frame: window)
        }
        #endif
        return .topBiased
    }

    #if canImport(Vision) && os(iOS)
    /// All faces' bounding box in unit image coordinates (top-left origin)
    private static func faces(in image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
        let boxes = (request.results ?? []).map(\.boundingBox)
        guard var union = boxes.first else { return nil }
        boxes.dropFirst().forEach { union = union.union($0) }
        // Vision's origin is bottom-left
        return CGRect(x: union.minX, y: 1 - union.maxY, width: union.width, height: union.height)
    }
    #endif
}

#if canImport(Vision) && os(iOS)
private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif

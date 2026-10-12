import SwiftUI
import FavWidgetsCore

/// A full-screen photo you can pinch, double-tap and pan, like Photos
/// (Wes, 2026-10-12). Shows `previewURL` (already cached from the grid)
/// while the full image loads. Zoom resets when `isCurrent` turns false, so
/// a photo swiped away comes back unzoomed.
struct ZoomableRemoteImage: View {
    let url: URL?
    var previewURL: URL?
    var isCurrent = true
    @State private var image: PostcardPlatformImage?
    @State private var preview: PostcardPlatformImage?

    var body: some View {
        Group {
            if let shown = image ?? preview {
                #if os(iOS)
                ZoomableImageView(image: shown, isCurrent: isCurrent)
                #else
                Image(nsImage: shown).resizable().scaledToFit()
                #endif
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            if let previewURL, image == nil { preview = await RemoteImageCache.image(for: previewURL) }
            if let url { image = await RemoteImageCache.image(for: url) }
        }
    }
}

#if os(iOS)
import UIKit

/// UIScrollView zooming: pinch 1×–5×, double-tap to 2.5× at the tap (or
/// back to 1×), pan while zoomed. At 1× its content fits the screen, so a
/// sideways swipe still pages the album.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isCurrent: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        scroll.accessibilityHint = "Pinch or double-tap to zoom"
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
        }
        if !isCurrent && scroll.zoomScale != 1 {
            scroll.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = recognizer.view as? UIScrollView, let imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}
#endif

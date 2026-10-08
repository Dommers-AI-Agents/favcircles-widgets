import Testing
import CoreGraphics
@testable import FavWidgetsCore

/// Placing a photo in the postcard window.
struct PostcardCropTests {
    let portrait = CGSize(width: 3000, height: 4000)   // a phone photo
    let window = CGSize(width: 600, height: 400)

    @Test func centeredFillsWithTheOverflowSplitEvenly() {
        let (size, offset) = PostcardCrop.centered.layout(image: portrait, frame: window)
        #expect(size == CGSize(width: 600, height: 800))
        #expect(offset == .zero)
    }

    @Test func slidingToTheTopShowsTheTopEdge() {
        let crop = PostcardCrop.centered.panned(dx: 0, dy: 1000, image: portrait, frame: window)
        #expect(crop.y == 1)      // clamped: the image's top meets the window's top
        let (size, offset) = crop.layout(image: portrait, frame: window)
        #expect(offset.height == (size.height - window.height) / 2)
    }

    @Test func aPositionCanNeverLeaveAGap() {
        let wild = PostcardCrop(zoom: 9, x: 5, y: -7)
        #expect(wild.zoom == PostcardCrop.maxZoom && wild.x == 1 && wild.y == -1)
        #expect(PostcardCrop(zoom: 0.2).zoom == 1)
        // A landscape photo that exactly fits has nowhere to slide sideways
        let fits = PostcardCrop.centered.panned(dx: 50, dy: 0, image: CGSize(width: 600, height: 400), frame: window)
        #expect(fits.x == 0)
    }

    @Test func zoomingKeepsTheMiddleWhereItWas() {
        let crop = PostcardCrop(zoom: 1, x: 0, y: 0.5)
        let zoomed = crop.zoomed(to: 2, image: portrait, frame: window)
        #expect(zoomed.zoom == 2)
        let before = crop.layout(image: portrait, frame: window).offset.height
        let after = zoomed.layout(image: portrait, frame: window).offset.height
        #expect(abs(after - before * 2) < 0.001)
    }

    @Test func facesNearTheTopMoveTheWindowUp() {
        let faces = CGRect(x: 0.4, y: 0.1, width: 0.2, height: 0.15)
        let crop = PostcardCrop.centering(on: faces, image: portrait, frame: window)
        #expect(crop.y > 0)
        #expect(crop.x == 0)
    }
}

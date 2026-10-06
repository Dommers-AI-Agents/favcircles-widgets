import SwiftUI
import FavWidgetsCore
#if canImport(UserNotifications) && !os(macOS)
import UserNotifications
import ImageIO
import UniformTypeIdentifiers

/// Coach Mane himself in his reminders: an animated GIF of him shouting,
/// attached to each notification — a thumbnail beside the line, and
/// moving when the notification is pressed open. Drawn from `CoachView`
/// frames (no assets), rendered once and cached.
@MainActor
enum CoachNotificationArt {
    private static let version = 1
    private static let frameCount = 18
    private static let frameDelay = 0.07

    /// The cached GIF, rendering it on first use. nil when it can't be made.
    static func gifURL() -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = caches.appendingPathComponent("coach-mane-shout-v\(version).gif")
        if fm.fileExists(atPath: url.path) { return url }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
        for i in 0..<frameCount {
            // Inside a shout burst, so every frame is mid-yell
            let t = 0.2 + Double(i) * frameDelay
            let renderer = ImageRenderer(content: frame(t: t))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { return nil }
            CGImageDestinationAddImage(destination, cg, frameProps)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    private static func frame(t: Double) -> some View {
        CoachView(shouting: true, size: 150).figure(t: t)
            .frame(width: 180, height: 180)
            .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    }

    /// One attachment per notification: iOS moves the file it's given, so
    /// each gets its own copy of the GIF.
    static func attachment() -> UNNotificationAttachment? {
        guard let gif = gifURL() else { return nil }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("coach-\(UUID().uuidString).gif")
        guard (try? FileManager.default.copyItem(at: gif, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "coach", url: copy, options: [
            UNNotificationAttachmentOptionsThumbnailTimeKey: 0.5
        ])
    }
}
#endif

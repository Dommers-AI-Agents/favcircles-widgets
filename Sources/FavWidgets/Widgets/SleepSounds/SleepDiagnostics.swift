import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// A small on-phone log of what happened to Sleep Sounds' audio: play,
/// pause, interruptions (with iOS's reason), route and configuration
/// changes, engine start failures, and the session's state when the app goes
/// to the background. Wes, 2026-10-31: "Sleep sounds are shutting off when I
/// lock the phone" — the code reads correct, so this records the cause on the
/// device that has the problem. Last 300 lines, in Application Support;
/// nothing leaves the phone.
public enum SleepDiagnostics {
    private static let maxLines = 300
    private static let queue = DispatchQueue(label: "sleepsounds.diagnostics")

    public static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FavWidgets", isDirectory: true)
            .appendingPathComponent("sleep-diagnostics.log")
    }

    static func note(_ event: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(event)\n"
        queue.async {
            guard let url = fileURL else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            lines.append(String(line.dropLast()))
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    #if os(iOS)
    /// The shared session as it is right now
    static func sessionState() -> String {
        let s = AVAudioSession.sharedInstance()
        return "category=\(s.category.rawValue) mode=\(s.mode.rawValue) otherAudio=\(s.isOtherAudioPlaying) route=\(s.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))"
    }
    #endif
}

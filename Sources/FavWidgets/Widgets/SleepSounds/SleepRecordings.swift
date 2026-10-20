import Foundation
import FavWidgetsCore
#if canImport(AVFoundation)
import AVFoundation

/// The nature sounds and the heartbeat as real recordings (Wes, 2026-10-19:
/// the synthesized rain "sounds like a machine"). Public-domain (CC0) field
/// recordings from Freesound, cut into seamless loops (the end crossfades
/// into the start; the heartbeat's loop is a whole number of beats) and
/// level-matched; see Resources/SleepSounds/SOURCES.md.
///
/// Each one is an AVAudioPlayerNode looping its file from disk (no decoded
/// copy in memory), with the mixer's level × master × sleep-timer fade as
/// its volume. A sound without a file falls back to its synthesized voice.
final class SleepRecordings {
    /// The kinds that have a recording in the bundle
    static let available: Set<SleepSoundKind> = Set(SleepSoundKind.allCases.filter { url(for: $0) != nil })

    static func url(for kind: SleepSoundKind) -> URL? {
        Bundle.module.url(forResource: "sleep-\(kind.rawValue)", withExtension: "m4a")
    }

    private struct Track {
        let node: AVAudioPlayerNode
        let file: AVAudioFile
    }

    private var tracks: [SleepSoundKind: Track] = [:]
    private let lock = NSLock()
    private var looping = false

    /// Attaches a looping player per recording to `engine`'s main mixer.
    /// Call before `engine.start()`.
    func attach(to engine: AVAudioEngine) {
        for kind in Self.available {
            guard let url = Self.url(for: kind), let file = try? AVAudioFile(forReading: url) else { continue }
            let node = AVAudioPlayerNode()
            node.volume = 0
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            tracks[kind] = Track(node: node, file: file)
        }
    }

    /// Starts every loop (silent until its volume comes up). Call after
    /// `engine.start()`, and again after the engine restarts: a stopped
    /// engine leaves its player nodes stopped.
    func start() {
        lock.lock(); let first = !looping; looping = true; lock.unlock()
        for (_, track) in tracks {
            if first {
                // Two copies queued so the next one is always ready; each
                // finished copy queues another, so it loops without a gap.
                schedule(track)
                schedule(track)
            }
            if !track.node.isPlaying { track.node.play() }
        }
    }

    func stop() {
        lock.lock(); looping = false; lock.unlock()
        for (_, track) in tracks { track.node.stop() }
        tracks.removeAll()
    }

    /// Volume = the sound's level × master × the sleep timer's fade
    func setVolumes(levels: [String: Double], master: Double, fade: Float) {
        for (kind, track) in tracks {
            let level = levels[kind.rawValue] ?? 0
            track.node.volume = Float(level * master) * fade
        }
    }

    private func schedule(_ track: Track) {
        track.node.scheduleFile(track.file, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); let again = self.looping; self.lock.unlock()
            if again { self.schedule(track) }
        }
    }
}
#endif

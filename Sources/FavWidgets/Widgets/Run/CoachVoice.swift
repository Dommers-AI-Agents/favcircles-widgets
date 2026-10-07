import Foundation
import FavWidgetsCore
#if os(iOS)
import AVFoundation
#endif

/// Coach Mane's voice during a FavRun (2026-10-07). His lines are spoken by a
/// directed cloud voice (`/widgets/run/coach-voice`, a gravelly drill
/// sergeant via Google's Gemini TTS — it takes ~6–10 s, fine a few seconds
/// after the mile ticks); with
/// no signal, or if that's slow, the phone's own voice says it instead. He
/// speaks over (ducks) your music, then hands the audio back. Works with the
/// phone locked: the run's background location keeps the app awake and the
/// app has the `audio` background mode.
@MainActor
final class CoachVoice: NSObject {
    static let shared = CoachVoice()
    /// How long to wait for the cloud voice before the phone's voice speaks
    static let cloudTimeout: UInt64 = 20_000_000_000

    #if os(iOS)
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var currentLine = UUID()

    private override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, intensity: MotivationIntensity = .savage, context: WidgetContext?) {
        guard !text.isEmpty else { return }
        let line = UUID()
        currentLine = line
        // Heard before (or fetched ahead): instant
        if let audio = Self.cached(text, intensity), play(audio) { return }
        guard let context else { speakOnDevice(text); return }
        Task { @MainActor in
            let audio = await Self.fetch(text, intensity: intensity, context: context)
            guard self.currentLine == line else { return }   // muted or replaced meanwhile
            if let audio, self.play(audio) { return }
            self.speakOnDevice(text)
        }
    }

    func stop() {
        currentLine = UUID()
        player?.stop(); player = nil
        synth.stopSpeaking(at: .immediate)
        releaseAudio()
    }

    /// Fetches a line ahead of time (the hello, when FavRun opens) so
    /// turning him on speaks at once instead of after the ~6 s it takes.
    func prefetch(_ text: String, intensity: MotivationIntensity, context: WidgetContext) {
        guard Self.cached(text, intensity) == nil else { return }
        Task { _ = await Self.fetch(text, intensity: intensity, context: context) }
    }

    private static func fetch(_ text: String, intensity: MotivationIntensity, context: WidgetContext) async -> Data? {
        let audio = await withTaskGroup(of: Data?.self) { group in
            group.addTask { try? await RunShareClient(context: context).coachVoice(text, intensity: intensity) }
            group.addTask { try? await Task.sleep(nanoseconds: cloudTimeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let audio { store(audio, text, intensity) }
        return audio
    }

    // Lines kept on the phone (Caches: the system may clear them; they're refetched)
    private static func cacheFile(_ text: String, _ intensity: MotivationIntensity) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CoachMane-v2", isDirectory: true) else { return nil } // v2: one voice for both levels
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (intensity.rawValue + "|" + text).utf8.reduce(into: UInt64(14_695_981_039_346_656_037)) { h, b in
            h = (h ^ UInt64(b)) &* 1_099_511_628_211
        }
        return dir.appendingPathComponent(String(name, radix: 16) + ".mp3")
    }
    private static func cached(_ text: String, _ intensity: MotivationIntensity) -> Data? {
        cacheFile(text, intensity).flatMap { try? Data(contentsOf: $0) }
    }
    private static func store(_ audio: Data, _ text: String, _ intensity: MotivationIntensity) {
        guard let url = cacheFile(text, intensity) else { return }
        try? audio.write(to: url, options: .atomic)
    }

    private func claimAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    private func releaseAudio() {
        // Music comes back up
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func play(_ data: Data) -> Bool {
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        claimAudio()
        p.delegate = self
        p.volume = 1
        player = p
        return p.play()
    }

    private func speakOnDevice(_ text: String) {
        claimAudio()
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice
        synth.speak(u)
    }

    /// The best installed English voice (enhanced/premium if the phone has one)
    private static let voice: AVSpeechSynthesisVoice? = {
        let lang = Locale.current.language.languageCode?.identifier == "en" ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: lang)
    }()
    #else
    func say(_ text: String, intensity: MotivationIntensity = .savage, context: WidgetContext?) {}
    func prefetch(_ text: String, intensity: MotivationIntensity, context: WidgetContext) {}
    func stop() {}
    #endif
}

#if os(iOS)
extension CoachVoice: AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synth.isSpeaking && self.player?.isPlaying != true { self.releaseAudio() } }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if !self.synth.isSpeaking { self.player = nil; self.releaseAudio() } }
    }
}
#endif

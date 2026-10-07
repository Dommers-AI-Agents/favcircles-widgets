import Foundation
import FavWidgetsCore
#if os(iOS)
import AVFoundation
#endif

/// Coach Mane's voice during a FavRun (2026-10-07). His lines are spoken by a
/// natural cloud voice (`/widgets/run/coach-voice`, Google Chirp 3 HD); with
/// no signal, or if that's slow, the phone's own voice says it instead. He
/// speaks over (ducks) your music, then hands the audio back. Works with the
/// phone locked: the run's background location keeps the app awake and the
/// app has the `audio` background mode.
@MainActor
final class CoachVoice: NSObject {
    static let shared = CoachVoice()
    /// How long to wait for the cloud voice before the phone's voice speaks
    static let cloudTimeout: UInt64 = 6_000_000_000

    #if os(iOS)
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var currentLine = UUID()

    private override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, context: WidgetContext?) {
        guard !text.isEmpty else { return }
        let line = UUID()
        currentLine = line
        guard let context else { speakOnDevice(text); return }
        Task { @MainActor in
            let audio = await Self.fetch(text, context: context)
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

    private static func fetch(_ text: String, context: WidgetContext) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { try? await RunShareClient(context: context).coachVoice(text) }
            group.addTask { try? await Task.sleep(nanoseconds: cloudTimeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
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
    func say(_ text: String, context: WidgetContext?) {}
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

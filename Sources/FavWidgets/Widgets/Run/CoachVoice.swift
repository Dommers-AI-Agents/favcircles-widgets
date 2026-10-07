import Foundation
import FavWidgetsCore
#if os(iOS)
import AVFoundation
#endif

/// Coach Mane's voice during a FavRun (2026-10-07). Speaks over (ducks)
/// your music or podcast, then hands the audio back. Works with the phone
/// locked: the run's background location keeps the app awake and the app
/// has the `audio` background mode.
@MainActor
final class CoachVoice: NSObject {
    static let shared = CoachVoice()

    #if os(iOS)
    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String) {
        guard !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice
        u.rate = 0.53          // a touch quicker than normal: he's yelling, not reading
        u.pitchMultiplier = 0.9
        u.volume = 1
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    /// The best installed English voice (enhanced/premium if the phone has one)
    private static let voice: AVSpeechSynthesisVoice? = {
        let lang = Locale.current.language.languageCode?.identifier == "en" ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: lang)
    }()
    #else
    func say(_ text: String) {}
    func stop() {}
    #endif
}

#if os(iOS)
extension CoachVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synth.isSpeaking else { return }
            // Music comes back up
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
#endif

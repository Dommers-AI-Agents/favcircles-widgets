import Foundation
import Combine
import FavWidgetsCore
#if canImport(AVFoundation)
import AVFoundation
#endif
#if os(iOS)
import MediaPlayer
import UIKit
#endif

/// The one player. Process-wide on purpose: the widget views come and go
/// with the home tab, and the sound must not stop because someone opened
/// Messages at 2 am. Owns the audio session, the sleep timer, lock-screen
/// controls, and the session log callback.
@MainActor
public final class SleepSoundEngine: ObservableObject {
    public static let shared = SleepSoundEngine()

    @Published public private(set) var isPlaying = false
    @Published public private(set) var levels: [String: Double] = [:]
    @Published public private(set) var mixName: String = SleepMix.builtIns[0].name
    @Published public private(set) var masterVolume: Double = 0.8
    @Published public private(set) var timerMinutes: Int = 45
    @Published public private(set) var timerEndsAt: Date?
    @Published public private(set) var lastError: String?
    /// Ticks once a second while playing so views can show time left.
    @Published public private(set) var now = Date()

    /// Called on stop with the finished session; the widget writes it into
    /// that month's shard.
    public var onSessionEnded: ((SleepSession) -> Void)?
    /// Set once the saved settings have been loaded into a fresh engine, so
    /// a later view appearance doesn't overwrite what the person changed.
    public var hasBeenTouched = false

    private var mixer: SleepMixer
    /// The sleep timer's fade, 1 → 0 (the recordings follow it too)
    private var fade: Float = 1
    private var sessionStartedAt: Date?
    private var ticker: Timer?
    private var pausedByInterruption = false
    #if canImport(AVFoundation)
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var recordings: SleepRecordings?
    private var observers: [NSObjectProtocol] = []
    #endif

    private init() {
        #if os(iOS)
        let rate = Float(AVAudioSession.sharedInstance().sampleRate > 0 ? AVAudioSession.sharedInstance().sampleRate : 48000)
        #else
        let rate: Float = 48000
        #endif
        mixer = SleepMixer(sampleRate: rate)
        mixer.setLevels(Self.synthesized(SleepMix.builtIns[0].levels))
        levels = SleepMix.builtIns[0].levels
    }

    /// The levels the synthesizer plays: everything but the sounds that
    /// have a recording (those play from their files instead)
    private static func synthesized(_ levels: [String: Double]) -> [String: Double] {
        #if canImport(AVFoundation)
        return levels.filter { key, _ in SleepSoundKind(rawValue: key).map { !SleepRecordings.available.contains($0) } ?? true }
        #else
        return levels
        #endif
    }

    private static func isRecorded(_ kind: SleepSoundKind) -> Bool {
        #if canImport(AVFoundation)
        return SleepRecordings.available.contains(kind)
        #else
        return false
        #endif
    }

    private func applyRecordingVolumes() {
        #if canImport(AVFoundation)
        recordings?.setVolumes(levels: levels, master: masterVolume, fade: fade)
        #endif
    }

    private func setFade(_ value: Float) {
        fade = min(1, max(0, value))
        mixer.setFade(fade)
        applyRecordingVolumes()
    }

    public var remaining: TimeInterval? {
        guard let timerEndsAt else { return nil }
        return max(0, timerEndsAt.timeIntervalSince(now))
    }

    public var activeSoundCount: Int { levels.values.filter { $0 > 0.001 }.count }

    // MARK: - Mix

    /// Replaces the whole mix (a preset or a saved mix).
    public func load(levels: [String: Double], name: String) {
        self.levels = levels
        mixName = name
        mixer.setLevels(Self.synthesized(levels))
        applyRecordingVolumes()
        updateNowPlaying()
    }

    public func setLevel(_ level: Double, for soundId: String) {
        guard let kind = SleepSoundKind(rawValue: soundId) else { return }
        let clamped = min(1, max(0, level))
        if clamped < 0.001 { levels.removeValue(forKey: soundId) } else { levels[soundId] = clamped }
        mixer.setLevel(Self.isRecorded(kind) ? 0 : clamped, for: kind)
        applyRecordingVolumes()
        mixName = SleepMix.describe(levels: levels)
        updateNowPlaying()
    }

    public func toggle(_ soundId: String) {
        setLevel((levels[soundId] ?? 0) > 0.001 ? 0 : 0.7, for: soundId)
    }

    public func setMasterVolume(_ volume: Double) {
        masterVolume = min(1, max(0, volume))
        mixer.setMaster(masterVolume)
        applyRecordingVolumes()
    }

    // MARK: - Timer

    public func setTimer(minutes: Int) {
        timerMinutes = max(0, minutes)
        if isPlaying { armTimer() } else { timerEndsAt = nil }
        updateNowPlaying()
    }

    private func armTimer() {
        timerEndsAt = timerMinutes > 0 ? Date().addingTimeInterval(TimeInterval(timerMinutes * 60)) : nil
        setFade(1)
    }

    // MARK: - Transport

    /// Starts playback. Synchronous so it can run straight from a tap.
    public func play() {
        guard !isPlaying else { return }
        #if canImport(AVFoundation)
        do {
            try activateSession()
            try startEngine()
        } catch {
            lastError = error.localizedDescription
            return
        }
        #endif
        isPlaying = true
        lastError = nil
        if sessionStartedAt == nil { sessionStartedAt = Date() }
        mixer.setMaster(masterVolume)
        armTimer()
        applyRecordingVolumes()
        mixer.snap()
        startTicker()
        installRemoteCommands()
        updateNowPlaying()
    }

    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        timerEndsAt = nil
        stopTicker()
        #if canImport(AVFoundation)
        engine?.pause()
        #endif
        updateNowPlaying()
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Ends the night: stops audio, releases the session so music or
    /// podcasts can resume, and logs the session.
    public func stop() {
        let wasPlaying = isPlaying
        isPlaying = false
        timerEndsAt = nil
        stopTicker()
        #if canImport(AVFoundation)
        recordings?.stop()
        recordings = nil
        engine?.stop()
        engine = nil
        source = nil
        deactivateSession()
        #endif
        if let startedAt = sessionStartedAt {
            let seconds = Int(Date().timeIntervalSince(startedAt))
            sessionStartedAt = nil
            if seconds >= 60 { onSessionEnded?(SleepSession(startedAt: startedAt, seconds: seconds, mixName: mixName)) }
        }
        _ = wasPlaying
        setFade(1)
        clearNowPlaying()
    }

    // MARK: - Ticker

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        guard let remaining else { return }
        setFade(SleepTimer.fadeGain(remaining: remaining))
        if remaining <= 0 { stop() }
        else if Int(remaining) % 30 == 0 { updateNowPlaying() }
    }

    // MARK: - Audio plumbing

    #if canImport(AVFoundation)
    private func activateSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
        installSessionObservers()
    }

    private func deactivateSession() {
        #if os(iOS)
        // Fails harmlessly if something else in the app still holds it.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func startEngine() throws {
        if let engine, engine.isRunning { return }
        if let engine, !engine.isRunning, source != nil {
            try engine.start()
            recordings?.start()
            return
        }
        let engine = AVAudioEngine()
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48000
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        // Filters and pitches are tuned per sample rate; if the hardware
        // runs at a different rate than the mixer was built for, rebuild it
        // with the same levels so nothing sounds transposed.
        if abs(mixer.sampleRate - Float(rate)) > 1 {
            let rebuilt = SleepMixer(sampleRate: Float(rate))
            rebuilt.setLevels(Self.synthesized(levels))
            rebuilt.setMaster(masterVolume)
            mixer = rebuilt
        }
        let mixer = self.mixer
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let data = first.mData else { return noErr }
            let out = data.assumingMemoryBound(to: Float.self)
            mixer.render(into: out, frames: Int(frameCount))
            // Mono format, but copy to any extra buffers defensively.
            for buffer in buffers.dropFirst() {
                if let extra = buffer.mData { extra.copyMemory(from: data, byteCount: Int(frameCount) * MemoryLayout<Float>.size) }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        // The recorded sounds, each looping its file
        let recordings = SleepRecordings()
        recordings.attach(to: engine)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        recordings.start()
        self.engine = engine
        self.source = source
        self.recordings = recordings
        applyRecordingVolumes()
    }

    private func installSessionObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        })
        #endif
    }

    private func handleConfigurationChange() {
        guard isPlaying, let engine, !engine.isRunning else { return }
        try? engine.start()
        recordings?.start()
    }

    #if os(iOS)
    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isPlaying { pausedByInterruption = true; pause() }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if pausedByInterruption && options.contains(.shouldResume) { play() }
            pausedByInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headphones pulled out: don't blast the room.
        if reason == .oldDeviceUnavailable, isPlaying { pause() }
    }
    #endif
    #endif

    // MARK: - Lock screen

    private func installRemoteCommands() {
        #if os(iOS)
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        #endif
    }

    private func updateNowPlaying() {
        #if os(iOS)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: mixName,
            MPMediaItemPropertyArtist: "Sleep Sounds · FavCircles",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let remaining {
            info[MPMediaItemPropertyPlaybackDuration] = remaining
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    private func clearNowPlaying() {
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }
}

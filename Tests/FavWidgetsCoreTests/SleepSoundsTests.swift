import Testing
import Foundation
@testable import FavWidgetsCore

struct SleepSoundsTests {
    private static let rate: Float = 48000

    /// Renders `seconds` of one voice at full level and returns the samples.
    private static func render(_ kind: SleepSoundKind, seconds: Float = 2, seed: UInt32 = 7) -> [Float] {
        let voice = SleepVoiceFactory.make(kind, sampleRate: rate, seed: seed)
        let frames = Int(rate * seconds)
        var out = [Float](repeating: 0, count: frames)
        out.withUnsafeMutableBufferPointer { buf in
            // Render in audio-sized blocks so per-block state paths run.
            var offset = 0
            while offset < frames {
                let n = min(512, frames - offset)
                voice.render(into: buf.baseAddress! + offset, frames: n, gain: 1)
                offset += n
            }
        }
        return out
    }

    private static func rms(_ x: ArraySlice<Float>) -> Float {
        sqrt(x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count)))
    }

    /// Energy below ~200 Hz versus the whole, via a one-pole low-pass.
    private static func lowBandFraction(_ x: [Float]) -> Float {
        var lp = OnePole(cutoffHz: 200, sampleRate: rate)
        var low: Float = 0, total: Float = 0
        for s in x { let l = lp.low(s); low += l * l; total += s * s }
        return total > 0 ? low / total : 0
    }

    @Test(arguments: SleepSoundKind.allCases)
    func everyVoiceIsAudibleBoundedAndFinite(kind: SleepSoundKind) {
        let x = Self.render(kind, seconds: 4)
        #expect(x.allSatisfy { $0.isFinite })
        #expect(x.allSatisfy { abs($0) <= 1.0001 }, "\(kind) exceeds ±1")
        // Loud enough to hear at a normal level, but with headroom for a mix.
        let level = Self.rms(x[...])
        #expect(level > 0.01 && level < 0.6, "\(kind) rms \(level)")
    }

    @Test func noiseColoursHaveTheRightTilt() {
        let white = Self.lowBandFraction(Self.render(.white))
        let pink = Self.lowBandFraction(Self.render(.pink))
        let brown = Self.lowBandFraction(Self.render(.brown))
        #expect(white < pink && pink < brown, "white \(white) pink \(pink) brown \(brown)")
        #expect(brown > 0.5)
        #expect(white < 0.05)
    }

    @Test func rainIsBrightAndThunderIsDeep() {
        #expect(Self.lowBandFraction(Self.render(.rain)) < 0.1)
        #expect(Self.lowBandFraction(Self.render(.thunder, seconds: 6)) > 0.8)
        #expect(Self.lowBandFraction(Self.render(.heartbeat, seconds: 3)) > 0.7)
    }

    @Test func oceanSwellsAndCricketsChirp() {
        // Ocean: loudness varies across the wave period.
        let ocean = Self.render(.ocean, seconds: 12)
        let block = Int(Self.rate)
        var levels: [Float] = []
        for i in stride(from: 0, to: ocean.count, by: block) { levels.append(Self.rms(ocean[i..<min(ocean.count, i + block)])) }
        #expect(levels.max()! > levels.min()! * 1.5)
        // Crickets: mostly silence with bursts.
        let crickets = Self.render(.crickets, seconds: 3)
        let quiet = crickets.filter { abs($0) < 0.002 }.count
        #expect(Float(quiet) / Float(crickets.count) > 0.3)
        #expect(crickets.contains { abs($0) > 0.1 })
    }

    @Test func voicesAreDeterministicPerSeedAndDifferentAcrossSeeds() {
        let a = Self.render(.white, seconds: 0.1, seed: 3)
        let b = Self.render(.white, seconds: 0.1, seed: 3)
        let c = Self.render(.white, seconds: 0.1, seed: 4)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: Mixer

    private static func renderMixer(_ mixer: SleepMixer, frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        out.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, frames: frames) }
        return out
    }

    @Test func mixerSilentWhenNothingIsOn() {
        let mixer = SleepMixer(sampleRate: Self.rate)
        mixer.setMaster(1)
        mixer.snap()
        let out = Self.renderMixer(mixer, frames: 4096)
        #expect(out.allSatisfy { $0 == 0 })
    }

    @Test func mixerRampsInsteadOfStepping() {
        let mixer = SleepMixer(sampleRate: Self.rate)
        mixer.setMaster(1)
        mixer.snap()
        mixer.setLevels(["white": 1])
        // First block: gain climbs from 0, so the start is quieter than the end.
        let first = Self.renderMixer(mixer, frames: 4800)
        let head = Self.rms(first[0..<480])
        let tail = Self.rms(first[4320..<4800])
        #expect(head < tail * 0.7, "head \(head) tail \(tail)")
        // After a few blocks it's settled and steady.
        _ = Self.renderMixer(mixer, frames: 4800)
        let settled = Self.renderMixer(mixer, frames: 4800)
        let a = Self.rms(settled[0..<2400]), b = Self.rms(settled[2400..<4800])
        #expect(abs(a - b) < max(a, b) * 0.25)
    }

    @Test func mixerNeverClipsWithEverythingOn() {
        let mixer = SleepMixer(sampleRate: Self.rate)
        mixer.setMaster(1)
        mixer.setLevels(Dictionary(uniqueKeysWithValues: SleepSoundKind.allCases.map { ($0.rawValue, 1.0) }))
        mixer.snap()
        let out = Self.renderMixer(mixer, frames: Int(Self.rate) * 2)
        #expect(out.allSatisfy { abs($0) < 1.0 && $0.isFinite })
        #expect(Self.rms(out[...]) > 0.05)
    }

    @Test func fadeDrivesTheMixerToSilence() {
        let mixer = SleepMixer(sampleRate: Self.rate)
        mixer.setMaster(1)
        mixer.setLevels(["pink": 1])
        mixer.snap()
        mixer.setFade(0)
        var last: [Float] = []
        for _ in 0..<20 { last = Self.renderMixer(mixer, frames: 4800) }
        #expect(Self.rms(last[...]) < 0.001)
    }

    // MARK: Timer + copy

    @Test func fadeCurve() {
        #expect(SleepTimer.fadeGain(remaining: 600) == 1)
        #expect(SleepTimer.fadeGain(remaining: 60) == 1)
        #expect(SleepTimer.fadeGain(remaining: 0) == 0)
        let mid = SleepTimer.fadeGain(remaining: 30)
        #expect(abs(mid - 0.5) < 0.001)
        #expect(SleepTimer.fadeGain(remaining: 45) > mid && mid > SleepTimer.fadeGain(remaining: 15))
    }

    @Test func timerCopy() {
        #expect(SleepTimer.remainingText(1925) == "32 min")
        #expect(SleepTimer.remainingText(3900) == "1 h 05 min")
        #expect(SleepTimer.remainingText(40) == "under a minute")
        #expect(SleepTimer.choiceText(0) == "Off")
        #expect(SleepTimer.choiceText(45) == "45m")
        #expect(SleepTimer.choiceText(90) == "1h30")
        #expect(SleepTimer.choiceText(120) == "2h")
    }

    @Test func cardCopy() {
        #expect(SleepSoundsCopy.cardSummary(isPlaying: true, mixName: "Rainy Night", remaining: 1925, nightsThisMonth: 3) == "Playing Rainy Night · 32 min left")
        #expect(SleepSoundsCopy.cardSummary(isPlaying: true, mixName: "Rainy Night", remaining: nil, nightsThisMonth: 3) == "Playing Rainy Night")
        #expect(SleepSoundsCopy.cardSummary(isPlaying: false, mixName: "Rainy Night", remaining: nil, nightsThisMonth: 1) == "Rainy Night · 1 night this month")
        #expect(SleepSoundsCopy.cardSummary(isPlaying: false, mixName: "Rainy Night", remaining: nil, nightsThisMonth: 0) == "Rainy Night")
        #expect(SleepMix.describe(levels: ["rain": 0.8, "thunder": 0.3]) == "Rain + Thunder")
        #expect(SleepMix.describe(levels: ["rain": 0.8, "thunder": 0.3, "wind": 0.2]) == "Rain + 2 more")
        #expect(SleepMix.describe(levels: [:]) == "Silence")
    }

    @Test func settingsStartFromLastNightOrTheFirstPreset() {
        var s = SleepSoundsSettings()
        #expect(s.startingName == "Rainy Night")
        s.lastLevels = ["fan": 0.9]
        s.lastMixName = "Just a Fan"
        #expect(s.startingLevels == ["fan": 0.9])
        #expect(s.startingName == "Just a Fan")
    }

    @Test func monthMergesSessionsAndCountsNights() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = Date(timeIntervalSince1970: 1_789_000_000)
        let a = SleepSession(id: "a", startedAt: day1, seconds: 3600, mixName: "Rain")
        let b = SleepSession(id: "b", startedAt: day1.addingTimeInterval(7200), seconds: 900, mixName: "Rain")
        let c = SleepSession(id: "c", startedAt: day1.addingTimeInterval(86400), seconds: 120, mixName: "Fan")
        let merged = SleepSoundsMonth.merge(local: SleepSoundsMonth(sessions: [a]), remote: SleepSoundsMonth(sessions: [a, b, c]))
        #expect(merged.sessions.count == 3)
        // Two sessions on day 1 count once; the two-minute one on day 2 doesn't count.
        #expect(merged.nights(calendar: cal) == 1)
        #expect(merged.totalSeconds == 4620)
        #expect(SleepSoundsCopy.monthSummary(nights: 1, totalSeconds: 4620) == "1 night this month · 1.3 hours")
    }

    @Test func settingsMergeKeepsBothDevicesMixes() {
        let mine = SleepMix(id: "m1", name: "Mine", levels: ["rain": 1])
        let theirs = SleepMix(id: "m2", name: "Theirs", levels: ["fan": 1])
        let merged = SleepSoundsSettings.merge(local: SleepSoundsSettings(mixes: [mine]), remote: SleepSoundsSettings(mixes: [theirs, mine]))
        #expect(merged.mixes.map(\.id) == ["m1", "m2"])
    }
}

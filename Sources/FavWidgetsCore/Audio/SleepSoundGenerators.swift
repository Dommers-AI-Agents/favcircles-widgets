import Foundation

// Every Sleep Sounds voice is synthesized here, sample by sample, from
// noise and a few filters. No audio files: the package can't carry
// resources (see Package.swift), a night of rain would be tens of MB, and
// a generated sound never loops, so there is no seam to notice at 3 am.
//
// Pure Foundation so `swift test` can measure each voice on a Mac. The
// AVAudioEngine wrapper lives in FavWidgets.

/// xorshift32: fast, deterministic per seed, good enough for noise.
public struct NoiseRNG {
    private var state: UInt32

    public init(seed: UInt32 = 0x9E3779B9) { state = seed == 0 ? 1 : seed }

    /// Uniform in [-1, 1).
    @inline(__always)
    public mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) / 2147483648
    }

    /// Uniform in [0, 1).
    @inline(__always)
    public mutating func unit() -> Float { (next() + 1) * 0.5 }
}

/// One-pole low-pass (`lp`) and the matching high-pass (`input - lp`).
public struct OnePole {
    private var a: Float
    private var z: Float = 0

    public init(cutoffHz: Float, sampleRate: Float) {
        a = OnePole.coefficient(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    public static func coefficient(cutoffHz: Float, sampleRate: Float) -> Float {
        let x = exp(-2 * Float.pi * max(1, cutoffHz) / sampleRate)
        return 1 - x
    }

    public mutating func setCutoff(_ cutoffHz: Float, sampleRate: Float) {
        a = OnePole.coefficient(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    @inline(__always)
    public mutating func low(_ x: Float) -> Float {
        z += a * (x - z)
        return z
    }

    @inline(__always)
    public mutating func high(_ x: Float) -> Float { x - low(x) }
}

/// RBJ band-pass biquad (constant 0 dB peak gain).
public struct BandPass {
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    public init(centerHz: Float, q: Float, sampleRate: Float) {
        set(centerHz: centerHz, q: q, sampleRate: sampleRate)
    }

    public mutating func set(centerHz: Float, q: Float, sampleRate: Float) {
        let w0 = 2 * Float.pi * min(max(20, centerHz), sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * max(0.1, q))
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = -2 * cos(w0) / a0
        a2 = (1 - alpha) / a0
    }

    @inline(__always)
    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// A voice adds its signal into a buffer. Output stays within about ±1
/// at full level so the mixer's headroom math is simple.
public protocol SleepVoice: AnyObject {
    var kind: SleepSoundKind { get }
    /// Adds `frames` samples × `gain` into `out`.
    func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float)
}

public enum SleepVoiceFactory {
    public static func make(_ kind: SleepSoundKind, sampleRate: Float, seed: UInt32 = 0x9E3779B9) -> SleepVoice {
        switch kind {
        case .white: return WhiteNoiseVoice(sampleRate: sampleRate, seed: seed)
        case .pink: return PinkNoiseVoice(sampleRate: sampleRate, seed: seed)
        case .brown: return BrownNoiseVoice(sampleRate: sampleRate, seed: seed)
        case .rain: return RainVoice(sampleRate: sampleRate, seed: seed)
        case .thunder: return ThunderVoice(sampleRate: sampleRate, seed: seed)
        case .ocean: return OceanVoice(sampleRate: sampleRate, seed: seed)
        case .stream: return StreamVoice(sampleRate: sampleRate, seed: seed)
        case .wind: return WindVoice(sampleRate: sampleRate, seed: seed)
        case .crickets: return CricketsVoice(sampleRate: sampleRate, seed: seed)
        case .fire: return FireVoice(sampleRate: sampleRate, seed: seed)
        case .fan: return FanVoice(sampleRate: sampleRate, seed: seed)
        case .heartbeat: return HeartbeatVoice(sampleRate: sampleRate, seed: seed)
        }
    }
}

// MARK: - Noise colours

public final class WhiteNoiseVoice: SleepVoice {
    public let kind = SleepSoundKind.white
    private var rng: NoiseRNG
    public init(sampleRate: Float, seed: UInt32) { rng = NoiseRNG(seed: seed) }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        let g = gain * 0.35
        for i in 0..<frames { out[i] += rng.next() * g }
    }
}

/// Paul Kellet's pink filter: -3 dB/octave, the "softer white" most
/// people mean by white noise.
public final class PinkNoiseVoice: SleepVoice {
    public let kind = SleepSoundKind.pink
    private var rng: NoiseRNG
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    public init(sampleRate: Float, seed: UInt32) { rng = NoiseRNG(seed: seed) }

    @inline(__always)
    func next() -> Float {
        let w = rng.next()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return pink * 0.11
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        let g = gain * 0.9
        for i in 0..<frames { out[i] += next() * g }
    }
}

/// Leaky integration of white: -6 dB/octave, the deep rumble.
public final class BrownNoiseVoice: SleepVoice {
    public let kind = SleepSoundKind.brown
    private var rng: NoiseRNG
    private var z: Float = 0
    public init(sampleRate: Float, seed: UInt32) { rng = NoiseRNG(seed: seed) }

    @inline(__always)
    func next() -> Float {
        z = (z + 0.02 * rng.next()) / 1.02
        return z * 3.5
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        let g = gain * 0.8
        for i in 0..<frames { out[i] += max(-1, min(1, next())) * g }
    }
}

// MARK: - Nature

/// Steady hiss of rain (high-passed pink) with individual drops: short
/// decaying pings at random pitches, a few hundred a second.
public final class RainVoice: SleepVoice {
    public let kind = SleepSoundKind.rain
    private var rng: NoiseRNG
    private let pink: PinkNoiseVoice
    private var hp: OnePole
    private var lp: OnePole
    private let sampleRate: Float
    private struct Drop { var phase: Float = 0; var step: Float = 0; var env: Float = 0; var decay: Float = 0 }
    private var drops = [Drop](repeating: Drop(), count: 12)
    private var nextDrop = 0
    private let dropsPerSecond: Float = 180

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 11)
        pink = PinkNoiseVoice(sampleRate: sampleRate, seed: seed &+ 12)
        hp = OnePole(cutoffHz: 400, sampleRate: sampleRate)
        lp = OnePole(cutoffHz: 6000, sampleRate: sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        let p = dropsPerSecond / sampleRate
        for i in 0..<frames {
            var s = lp.low(hp.high(pink.next())) * 1.6
            if rng.unit() < p {
                let hz = 1200 + rng.unit() * 4000
                drops[nextDrop] = Drop(phase: 0, step: 2 * Float.pi * hz / sampleRate, env: 0.25 + rng.unit() * 0.35,
                                       decay: 1 - (60 + rng.unit() * 200) / sampleRate)
                nextDrop = (nextDrop + 1) % drops.count
            }
            for d in 0..<drops.count where drops[d].env > 0.001 {
                drops[d].phase += drops[d].step
                s += sin(drops[d].phase) * drops[d].env
                drops[d].env *= drops[d].decay
            }
            out[i] += max(-1, min(1, s)) * gain
        }
    }
}

/// A faint distant bed with a real rumble every 15–45 s: brown noise
/// shaped by a slow attack/long decay, kept below 120 Hz.
public final class ThunderVoice: SleepVoice {
    public let kind = SleepSoundKind.thunder
    private var rng: NoiseRNG
    private let brown: BrownNoiseVoice
    private var lp: OnePole
    private let sampleRate: Float
    private var untilNext: Int
    private var env: Float = 0
    private var attack: Float = 0
    private var decay: Float = 0
    private var peak: Float = 0
    private var rising = false

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 21)
        brown = BrownNoiseVoice(sampleRate: sampleRate, seed: seed &+ 22)
        lp = OnePole(cutoffHz: 110, sampleRate: sampleRate)
        untilNext = Int(sampleRate * 1.5)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            untilNext -= 1
            if untilNext <= 0 {
                let seconds = 15 + rng.unit() * 30
                untilNext = Int(seconds * sampleRate)
                peak = 0.5 + rng.unit() * 0.5
                attack = 1 / ((0.2 + rng.unit() * 0.6) * sampleRate)
                decay = 1 - 1 / ((3 + rng.unit() * 5) * sampleRate)
                rising = true
            }
            if rising {
                env += attack * peak
                if env >= peak { env = peak; rising = false }
            } else {
                env *= decay
            }
            let bed: Float = 0.16
            let s = lp.low(brown.next()) * (bed + env * 2.2)
            out[i] += max(-1, min(1, s)) * gain
        }
    }
}

/// Waves every ~11 s: brown noise swelling under a slow curve, with a
/// hiss of foam that peaks just after each swell.
public final class OceanVoice: SleepVoice {
    public let kind = SleepSoundKind.ocean
    private var rng: NoiseRNG
    private let brown: BrownNoiseVoice
    private var hiss: OnePole
    private var lp: OnePole
    private let sampleRate: Float
    private var phase: Float = 0
    private var period: Float = 11
    private var wobble: Float = 0

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 31)
        brown = BrownNoiseVoice(sampleRate: sampleRate, seed: seed &+ 32)
        hiss = OnePole(cutoffHz: 1500, sampleRate: sampleRate)
        lp = OnePole(cutoffHz: 500, sampleRate: sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            phase += 1 / (period * sampleRate)
            if phase >= 1 {
                phase -= 1
                period = 8 + rng.unit() * 6
                wobble = rng.unit() * 0.3
            }
            // Asymmetric swell: quick rise, slow retreat.
            let x = phase < 0.35 ? phase / 0.35 : 1 - (phase - 0.35) / 0.65
            let swell = x * x * (0.7 + wobble)
            let w = rng.next()
            let foam = hiss.high(w) * (swell * swell) * 0.45
            let body = lp.low(brown.next()) * (0.25 + swell)
            out[i] += max(-1, min(1, body + foam)) * gain
        }
    }
}

/// Water over rocks: white noise through a band-pass whose centre jitters
/// quickly, with a low gurgle underneath.
public final class StreamVoice: SleepVoice {
    public let kind = SleepSoundKind.stream
    private var rng: NoiseRNG
    private var band: BandPass
    private var band2: BandPass
    private let brown: BrownNoiseVoice
    private var lp: OnePole
    private let sampleRate: Float
    private var center: Float = 1600
    private var counter = 0
    private var lfo: Float = 0

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 41)
        band = BandPass(centerHz: 1600, q: 1.2, sampleRate: sampleRate)
        band2 = BandPass(centerHz: 3200, q: 2.5, sampleRate: sampleRate)
        brown = BrownNoiseVoice(sampleRate: sampleRate, seed: seed &+ 42)
        lp = OnePole(cutoffHz: 250, sampleRate: sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            counter += 1
            if counter >= 64 {
                counter = 0
                center = min(2600, max(900, center + rng.next() * 120))
                band.set(centerHz: center, q: 1.2, sampleRate: sampleRate)
            }
            lfo += 2 * Float.pi * 0.7 / sampleRate
            let mod = 0.75 + 0.25 * sin(lfo)
            let w = rng.next()
            let s = (band.process(w) * 2.2 + band2.process(w) * 0.9) * mod + lp.low(brown.next()) * 0.35
            out[i] += max(-1, min(1, s)) * gain
        }
    }
}

/// Wind: a resonant band of noise whose pitch wanders and whose strength
/// gusts on a slow random walk.
public final class WindVoice: SleepVoice {
    public let kind = SleepSoundKind.wind
    private var rng: NoiseRNG
    private var band: BandPass
    private var lp: OnePole
    private let sampleRate: Float
    private var center: Float = 400
    private var centerTarget: Float = 400
    private var level: Float = 0.5
    private var levelTarget: Float = 0.5
    private var counter = 0

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 51)
        band = BandPass(centerHz: 400, q: 2.5, sampleRate: sampleRate)
        lp = OnePole(cutoffHz: 1800, sampleRate: sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            counter += 1
            if counter >= 2048 {
                counter = 0
                if rng.unit() < 0.15 {
                    centerTarget = 150 + rng.unit() * 700
                    levelTarget = 0.25 + rng.unit() * 0.75
                }
                center += (centerTarget - center) * 0.08
                level += (levelTarget - level) * 0.06
                band.set(centerHz: center, q: 2.5, sampleRate: sampleRate)
            }
            let s = lp.low(band.process(rng.next())) * 3.2 * level
            out[i] += max(-1, min(1, s)) * gain
        }
    }
}

/// Field crickets: a handful of individuals, each chirping trains of
/// three short 4–5 kHz syllables, slightly out of step with the others.
public final class CricketsVoice: SleepVoice {
    public let kind = SleepSoundKind.crickets
    private var rng: NoiseRNG
    private let sampleRate: Float
    private struct Cricket {
        var phase: Float = 0
        var step: Float = 0
        var gapSamples: Int = 0
        var untilChirp: Int = 0
        var syllable = 0
        var inSyllable = 0
        var level: Float = 0.5
    }
    private var crickets: [Cricket] = []
    private let syllableSamples: Int
    private let syllableGap: Int

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 61)
        syllableSamples = Int(0.028 * sampleRate)
        syllableGap = Int(0.018 * sampleRate)
        for n in 0..<4 {
            var c = Cricket()
            c.step = 2 * Float.pi * (4200 + Float(n) * 180 + rng.unit() * 120) / sampleRate
            c.untilChirp = Int(rng.unit() * 0.8 * sampleRate)
            c.level = 0.3 + rng.unit() * 0.4
            c.syllable = 3
            crickets.append(c)
        }
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            var s: Float = 0
            for c in 0..<crickets.count {
                if crickets[c].syllable >= 3 {
                    crickets[c].untilChirp -= 1
                    if crickets[c].untilChirp <= 0 {
                        crickets[c].syllable = 0
                        crickets[c].inSyllable = 0
                        crickets[c].untilChirp = Int((0.5 + rng.unit() * 0.9) * sampleRate)
                    }
                    continue
                }
                if crickets[c].gapSamples > 0 {
                    crickets[c].gapSamples -= 1
                    continue
                }
                let t = Float(crickets[c].inSyllable) / Float(syllableSamples)
                let window = sin(t * Float.pi)
                crickets[c].phase += crickets[c].step
                s += sin(crickets[c].phase) * window * crickets[c].level
                crickets[c].inSyllable += 1
                if crickets[c].inSyllable >= syllableSamples {
                    crickets[c].inSyllable = 0
                    crickets[c].syllable += 1
                    crickets[c].gapSamples = syllableGap
                }
            }
            out[i] += s * 0.5 * gain
        }
    }
}

/// Campfire: low rumble plus a Poisson scatter of crackles, each a few
/// milliseconds of noise through a bright resonator.
public final class FireVoice: SleepVoice {
    public let kind = SleepSoundKind.fire
    private var rng: NoiseRNG
    private let brown: BrownNoiseVoice
    private var lp: OnePole
    private var crackleBand: BandPass
    private let sampleRate: Float
    private var crackleEnv: Float = 0
    private var crackleDecay: Float = 0
    private let cracklesPerSecond: Float = 9

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 71)
        brown = BrownNoiseVoice(sampleRate: sampleRate, seed: seed &+ 72)
        lp = OnePole(cutoffHz: 160, sampleRate: sampleRate)
        crackleBand = BandPass(centerHz: 2500, q: 1.5, sampleRate: sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        let p = cracklesPerSecond / sampleRate
        for i in 0..<frames {
            if rng.unit() < p {
                crackleEnv = 0.4 + rng.unit() * 0.6
                crackleDecay = 1 - 1 / ((0.003 + rng.unit() * 0.01) * sampleRate)
                crackleBand.set(centerHz: 1500 + rng.unit() * 3000, q: 1.5, sampleRate: sampleRate)
            }
            let crackle = crackleBand.process(rng.next()) * crackleEnv * 2.5
            crackleEnv *= crackleDecay
            let s = lp.low(brown.next()) * 0.7 + crackle
            out[i] += max(-1, min(1, s)) * gain
        }
    }
}

// MARK: - Indoors

/// A box fan: low-passed pink with a soft motor hum that breathes.
public final class FanVoice: SleepVoice {
    public let kind = SleepSoundKind.fan
    private var rng: NoiseRNG
    private let pink: PinkNoiseVoice
    private var lp: OnePole
    private let sampleRate: Float
    private var humPhase: Float = 0
    private var breathPhase: Float = 0

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 81)
        pink = PinkNoiseVoice(sampleRate: sampleRate, seed: seed &+ 82)
        lp = OnePole(cutoffHz: 900, sampleRate: sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            humPhase += 2 * Float.pi * 120 / sampleRate
            breathPhase += 2 * Float.pi * 0.4 / sampleRate
            let breath = 0.92 + 0.08 * sin(breathPhase)
            let hum = sin(humPhase) * 0.06 + sin(humPhase * 2) * 0.03
            let s = (lp.low(pink.next()) * 1.4 + hum) * breath
            out[i] += max(-1, min(1, s)) * gain
        }
    }
}

/// A resting heartbeat at 60 bpm: lub, then a softer dub 180 ms later.
public final class HeartbeatVoice: SleepVoice {
    public let kind = SleepSoundKind.heartbeat
    private var rng: NoiseRNG
    private var lp: OnePole
    private let sampleRate: Float
    private var t = 0
    private let beatSamples: Int
    private let dubOffset: Int
    private var lubEnv: Float = 0, dubEnv: Float = 0
    private var lubPhase: Float = 0, dubPhase: Float = 0
    private let lubDecay: Float, dubDecay: Float

    public init(sampleRate: Float, seed: UInt32) {
        self.sampleRate = sampleRate
        rng = NoiseRNG(seed: seed &+ 91)
        lp = OnePole(cutoffHz: 140, sampleRate: sampleRate)
        beatSamples = Int(sampleRate)
        dubOffset = Int(0.18 * sampleRate)
        lubDecay = 1 - 1 / (0.09 * sampleRate)
        dubDecay = 1 - 1 / (0.07 * sampleRate)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        for i in 0..<frames {
            if t == 0 { lubEnv = 1; lubPhase = 0 }
            if t == dubOffset { dubEnv = 0.7; dubPhase = 0 }
            t += 1
            if t >= beatSamples { t = 0 }
            lubPhase += 2 * Float.pi * 52 / sampleRate
            dubPhase += 2 * Float.pi * 44 / sampleRate
            let s = sin(lubPhase) * lubEnv + sin(dubPhase) * dubEnv
            lubEnv *= lubDecay
            dubEnv *= dubDecay
            out[i] += max(-1, min(1, lp.low(s) * 1.6)) * gain
        }
    }
}

// MARK: - Mixer

/// Sums the voices with click-free per-voice gain smoothing and a master
/// fade. `setLevel`/`setMaster` are called from the main thread; `render`
/// from the audio thread. The lock is taken once per render call to copy
/// targets, never per sample.
public final class SleepMixer {
    public let sampleRate: Float
    private let voices: [SleepVoice]
    private let lock = NSLock()
    private var targets: [Float]
    private var current: [Float]
    private var masterTarget: Float = 0.8
    private var masterCurrent: Float = 0
    private var fadeTarget: Float = 1
    /// Set under the lock by `snap()`, consumed on the audio thread: the
    /// smoothed state jumps to the targets on the next render. `current`
    /// and `masterCurrent` are touched only by the audio thread.
    private var snapRequested = false
    private var snapValues: [Float]
    private var snapMaster: Float = 0
    private var targetsSnapshot: [Float]
    private var scratch: [Float]
    private let smoothing: Float
    /// `1 - (1 - smoothing)^frames`, cached for the last block size.
    private var blockFrames = 0
    private var blockAlpha: Float = 0

    public init(sampleRate: Float, seed: UInt32 = 0x9E3779B9) {
        self.sampleRate = sampleRate
        voices = SleepSoundKind.allCases.map { SleepVoiceFactory.make($0, sampleRate: sampleRate, seed: seed &+ UInt32($0.rawValue.utf8.reduce(0) { $0 &+ Int($1) })) }
        targets = Array(repeating: 0, count: voices.count)
        current = targets
        targetsSnapshot = targets
        snapValues = targets
        scratch = Array(repeating: 0, count: 4096)
        // ~30 ms to settle: slow enough to hide slider steps, fast enough to feel instant.
        smoothing = 1 - exp(-1 / (0.03 * sampleRate))
    }

    public var kinds: [SleepSoundKind] { voices.map(\.kind) }

    public func setLevel(_ level: Double, for kind: SleepSoundKind) {
        guard let index = voices.firstIndex(where: { $0.kind == kind }) else { return }
        lock.lock(); targets[index] = Float(min(1, max(0, level))); lock.unlock()
    }

    public func setLevels(_ levels: [String: Double]) {
        lock.lock()
        for (index, voice) in voices.enumerated() {
            targets[index] = Float(min(1, max(0, levels[voice.kind.rawValue] ?? 0)))
        }
        lock.unlock()
    }

    public func setMaster(_ volume: Double) {
        lock.lock(); masterTarget = Float(min(1, max(0, volume))); lock.unlock()
    }

    /// The sleep timer's fade, 1 → 0. Applied on top of master.
    public func setFade(_ fade: Float) {
        lock.lock(); fadeTarget = min(1, max(0, fade)); lock.unlock()
    }

    /// Jump the smoothed state to the targets on the next render, for a
    /// clean start. Only the audio thread writes the smoothed state.
    public func snap() {
        lock.lock()
        for i in 0..<targets.count { snapValues[i] = targets[i] }
        snapMaster = masterTarget * fadeTarget
        snapRequested = true
        lock.unlock()
    }

    /// Mono render. Voices at zero (and settled) cost nothing.
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        lock.lock()
        for i in 0..<targets.count { targetsSnapshot[i] = targets[i] }
        let master = masterTarget * fadeTarget
        let snap = snapRequested
        if snap {
            for i in 0..<current.count { current[i] = snapValues[i] }
            masterCurrent = snapMaster
            snapRequested = false
        }
        lock.unlock()
        let t = targetsSnapshot
        if frames != blockFrames {
            blockFrames = frames
            blockAlpha = 1 - pow(1 - smoothing, Float(frames))
        }
        let alpha = blockAlpha

        if scratch.count < frames { scratch = Array(repeating: 0, count: frames) }
        for i in 0..<frames { out[i] = 0 }

        scratch.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for (index, voice) in voices.enumerated() {
                let target = t[index]
                var g = current[index]
                if target < 0.0005 && g < 0.0005 { current[index] = 0; continue }
                for i in 0..<frames { base[i] = 0 }
                // Per-voice gain is applied in the voice; smooth toward the
                // target across the block by rendering at the block's end
                // value and ramping the sum. Cheap and inaudible at 30 ms.
                let start = g
                g += (target - g) * alpha
                current[index] = g
                voice.render(into: base, frames: frames, gain: 1)
                let step = (g - start) / Float(max(1, frames))
                var ramp = start
                for i in 0..<frames {
                    out[i] += base[i] * ramp
                    ramp += step
                }
            }
        }

        // Master + fade, smoothed, then a soft knee so a loud mix can't clip.
        let mStart = masterCurrent
        masterCurrent += (master - masterCurrent) * alpha
        let mStep = (masterCurrent - mStart) / Float(max(1, frames))
        var m = mStart
        for i in 0..<frames {
            let x = out[i] * m
            out[i] = x > 0.8 ? 0.8 + 0.199 * tanh((x - 0.8) * 5) : (x < -0.8 ? -0.8 - 0.199 * tanh((-x - 0.8) * 5) : x)
            m += mStep
        }
    }
}

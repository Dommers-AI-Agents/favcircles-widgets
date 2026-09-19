import Foundation

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

import Foundation

// Every Sleep Sounds voice is synthesized here, sample by sample, from
// noise and a few filters. No audio files: the package can't carry
// resources (see Package.swift), a night of rain would be tens of MB, and
// a generated sound never loops, so there is no seam to notice at 3 am.
//
// Pure Foundation so `swift test` can measure each voice on a Mac. The
// AVAudioEngine wrapper lives in FavWidgets.

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

// MARK: - Indoors

// MARK: - Mixer


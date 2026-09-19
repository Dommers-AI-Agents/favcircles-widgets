import Foundation

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

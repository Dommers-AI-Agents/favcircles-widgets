import Foundation

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

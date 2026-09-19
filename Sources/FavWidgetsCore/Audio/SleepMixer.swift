import Foundation

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

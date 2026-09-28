import Foundation

// Heartbeat: a pulse reading from the phone's camera (fingertip over the
// lens and flash) or a Bluetooth heart-rate strap. Readings are logged into
// monthly shards, never pruned. Not a medical device, and the copy says so.

public enum HeartSource: String, Codable, Sendable {
    case camera, strap, watch
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HeartSource(rawValue: raw) ?? .unknown
    }

    public var label: String {
        switch self {
        case .camera: return "Camera"
        case .strap: return "Strap"
        case .watch: return "Watch"
        case .unknown: return "Reading"
        }
    }
}

public struct HeartReading: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var at: Date
    public var bpm: Int
    public var source: HeartSource
    /// 0…1, how clean the pulse signal was (camera only; straps report 1).
    public var confidence: Double

    public init(id: String = UUID().uuidString, at: Date, bpm: Int, source: HeartSource, confidence: Double = 1) {
        self.id = id
        self.at = at
        self.bpm = bpm
        self.source = source
        self.confidence = confidence
    }
}

/// Settings document: nothing much yet, but the storage kind needs one.
public struct HeartbeatSettings: WidgetModel {
    public var lastSource: HeartSource?
    public var lastStrapName: String?

    public init(lastSource: HeartSource? = nil, lastStrapName: String? = nil) {
        self.lastSource = lastSource
        self.lastStrapName = lastStrapName
    }

    public static let empty = HeartbeatSettings()
}

/// One month of readings.
public struct HeartbeatMonth: WidgetModel {
    public var readings: [HeartReading]

    public init(readings: [HeartReading] = []) { self.readings = readings }

    public static let empty = HeartbeatMonth()

    public var latest: HeartReading? { readings.max { $0.at < $1.at } }

    public var stats: (min: Int, avg: Int, max: Int)? {
        guard !readings.isEmpty else { return nil }
        let bpms = readings.map(\.bpm)
        return (bpms.min()!, Int((Double(bpms.reduce(0, +)) / Double(bpms.count)).rounded()), bpms.max()!)
    }

    public static func merge(local: HeartbeatMonth, remote: HeartbeatMonth) -> HeartbeatMonth {
        var merged = local
        for reading in remote.readings where !merged.readings.contains(where: { $0.id == reading.id }) {
            merged.readings.append(reading)
        }
        merged.readings.sort { $0.at < $1.at }
        return merged
    }
}

/// Pulse from a stream of brightness samples (the mean red of each camera
/// frame). Pure: feed samples with timestamps, ask for an estimate.
///
/// Method (2026-09-28 rewrite, after a 135 bpm pulse read 50):
/// 1. Resample the last window onto an even grid using the frames' own
///    timestamps. The camera drops frames; assuming a fixed 30 fps skewed
///    every answer.
/// 2. Detrend, then take the first difference. A heartbeat has a sharp
///    upstroke, so its slope is strong. The slow swell from breathing and a
///    moving hand is smooth, so differencing shrinks it. That swell sits at
///    40–60 "bpm", and the old autocorrelation locked onto it.
/// 3. Score each candidate rate by its spectral power plus that of its 2nd
///    and 3rd harmonics. A pulse is not a sine wave and has harmonics.
///    Breathing is nearly a sine and has almost none.
/// Confidence is the share of the signal's energy that sits on the chosen
/// rate and its harmonics.
public struct HeartRateEstimator: Sendable {
    public struct Estimate: Equatable, Sendable {
        public let bpm: Int
        public let confidence: Double
    }

    /// Harmonics counted per candidate rate. Six raised noise's scores more
    /// than a resting pulse's.
    static let harmonics = 4.0
    public let sampleRate: Double
    public let windowSeconds: Double
    public let minBPM: Double
    public let maxBPM: Double
    private var times: [Double] = []
    private var values: [Double] = []

    public init(sampleRate: Double = 30, windowSeconds: Double = 8, minBPM: Double = 40, maxBPM: Double = 200) {
        self.sampleRate = sampleRate
        self.windowSeconds = windowSeconds
        self.minBPM = minBPM
        self.maxBPM = maxBPM
    }

    /// Seconds of signal collected so far, capped at the window.
    public var secondsCollected: Double {
        guard let first = times.first, let last = times.last else { return 0 }
        return last - first
    }

    public var isReady: Bool { secondsCollected >= min(windowSeconds, 6) }

    public mutating func reset() {
        times.removeAll()
        values.removeAll()
    }

    public mutating func add(value: Double, at time: Double) {
        // Out-of-order or repeated timestamps would break the resampling.
        if let last = times.last, time <= last { return }
        times.append(time)
        values.append(value)
        // Keep a little more than the window so the detrend has context.
        let keepFrom = time - windowSeconds - 1
        if let cut = times.firstIndex(where: { $0 >= keepFrom }), cut > 0 {
            times.removeFirst(cut)
            values.removeFirst(cut)
        }
    }

    /// The most recent detrended samples, for drawing a waveform.
    public var waveform: [Double] {
        HeartRateEstimator.detrend(values, sampleRate: sampleRate)
    }

    public func estimate() -> Estimate? {
        guard isReady else { return nil }
        let uniform = HeartRateEstimator.resample(times: times, values: values, rate: sampleRate, seconds: windowSeconds)
        guard uniform.count >= Int(sampleRate * 4) else { return nil }
        let detrended = HeartRateEstimator.detrend(uniform, sampleRate: sampleRate)
        var slope = [Double](repeating: 0, count: detrended.count - 1)
        for i in 0..<slope.count { slope[i] = detrended[i + 1] - detrended[i] }
        let mean = slope.reduce(0, +) / Double(slope.count)
        let n = slope.count
        // Hann window keeps one strong line from smearing across the band.
        let windowed = (0..<n).map { i in
            (slope[i] - mean) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1)))
        }

        // Power on a 0.5 bpm grid, from the lowest candidate up to 3× the
        // highest (for harmonics), stopping short of Nyquist.
        let step = 0.5
        let nyquistBPM = sampleRate / 2 * 60 * 0.95
        let lowBPM = minBPM * 0.75
        let topBPM = min(maxBPM * HeartRateEstimator.harmonics, nyquistBPM)
        let count = Int(((topBPM - lowBPM) / step).rounded(.down)) + 1
        var power = [Double](repeating: 0, count: count)
        for k in 0..<count {
            power[k] = HeartRateEstimator.goertzel(windowed, hz: (lowBPM + Double(k) * step) / 60, rate: sampleRate)
        }
        let total = power.reduce(0, +)
        guard total > 0 else { return nil }
        func p(_ bpm: Double) -> Double {
            let k = Int(((bpm - lowBPM) / step).rounded())
            return k >= 0 && k < count ? power[k] : 0
        }
        func score(_ bpm: Double) -> Double {
            (1...Int(HeartRateEstimator.harmonics)).reduce(0) { $0 + p(Double($1) * bpm) }
        }

        var bestBPM = minBPM
        var best = -Double.infinity
        var bpm = minBPM
        while bpm <= maxBPM {
            let s = score(bpm)
            if s > best { best = s; bestBPM = bpm }
            bpm += step
        }
        // A sharp pulse has strong upper harmonics, so a rate at 2× or 3×
        // the real one can collect nearly as much. When a third or half of
        // the winner scores almost as well, the lower one is the heartbeat.
        for divisor in [3.0, 2.0] {
            let lower = ((bestBPM / divisor) / step).rounded() * step
            guard lower >= minBPM else { continue }
            let lowerScore = score(lower)
            // ...and only when the lower rate's own beat is really there.
            if lowerScore >= 0.65 * best && p(lower) >= 0.1 * p(bestBPM) {
                bestBPM = lower
                best = lowerScore
                break
            }
        }
        // Parabolic refine between grid points.
        var refined = bestBPM
        if bestBPM > minBPM && bestBPM < maxBPM {
            let sm = score(bestBPM - step), sp = score(bestBPM + step)
            let denom = sm - 2 * best + sp
            if abs(denom) > 1e-12 { refined += step * 0.5 * (sm - sp) / denom }
        }
        if !refined.isFinite || abs(refined - bestBPM) > step { refined = bestBPM }

        // Share of all energy within a few bpm of the rate and its harmonics
        // (the band widens with the harmonic, as beat-to-beat wobble does).
        var onPeak = 0.0
        for h in (1...Int(HeartRateEstimator.harmonics)).map(Double.init) {
            let width = 4 * h
            var b = h * bestBPM - width
            while b <= h * bestBPM + width { onPeak += p(b); b += step }
        }
        let confidence = max(0, min(1, onPeak / total * 1.2))
        return Estimate(bpm: Int(refined.rounded()), confidence: confidence)
    }

    /// Power of one frequency (Goertzel), normalized by length.
    static func goertzel(_ x: [Double], hz: Double, rate: Double) -> Double {
        let w = 2 * Double.pi * hz / rate
        let coeff = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x {
            let s0 = v + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        return max(0, power) / Double(x.count)
    }

    /// The last `seconds` of samples on an even grid at `rate`, by linear
    /// interpolation between the real frame times.
    static func resample(times: [Double], values: [Double], rate: Double, seconds: Double) -> [Double] {
        guard let first = times.first, let last = times.last, last > first else { return [] }
        let start = max(first, last - seconds)
        let dt = 1 / rate
        var out: [Double] = []
        out.reserveCapacity(Int(seconds * rate) + 1)
        var j = max(0, (times.firstIndex { $0 >= start } ?? 1) - 1)
        var t = start
        while t <= last {
            while j + 1 < times.count - 1 && times[j + 1] < t { j += 1 }
            let t0 = times[j], t1 = times[min(j + 1, times.count - 1)]
            let v0 = values[j], v1 = values[min(j + 1, values.count - 1)]
            let f = t1 > t0 ? min(1, max(0, (t - t0) / (t1 - t0))) : 0
            out.append(v0 + (v1 - v0) * f)
            t += dt
        }
        return out
    }

    static func detrend(_ x: [Double], sampleRate: Double) -> [Double] {
        let radius = max(1, Int(sampleRate / 2))
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - radius), hi = min(x.count - 1, i + radius)
            var sum = 0.0
            for j in lo...hi { sum += x[j] }
            out[i] = x[i] - sum / Double(hi - lo + 1)
        }
        return out
    }

    /// The middle of the recent estimates. The median ignores the odd wild
    /// one that a mean would drag the answer toward.
    public static func median(_ history: [Int]) -> Int? {
        guard !history.isEmpty else { return nil }
        let sorted = history.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : Int((Double(sorted[mid - 1] + sorted[mid]) / 2).rounded())
    }

    /// Whether most recent estimates agree with their median, within
    /// `tolerance` bpm. Noise wanders; a real pulse keeps landing in the
    /// same place. A reading without that agreement isn't worth showing.
    public static func hasConsensus(_ history: [Int], tolerance: Int = 5) -> Bool {
        guard let mid = median(history) else { return false }
        let agreeing = history.filter { abs($0 - mid) <= tolerance }.count
        return agreeing * 2 > history.count
    }

    /// A reading is steady when the last few estimates agree with each other.
    /// Used to stop early: once six consecutive estimates sit within
    /// `tolerance` bpm of their mean, more seconds would only confirm it.
    public static func isSteady(_ history: [Int], count: Int = 6, tolerance: Int = 3) -> Bool {
        guard history.count >= count else { return false }
        let recent = history.suffix(count)
        let mean = Double(recent.reduce(0, +)) / Double(recent.count)
        return recent.allSatisfy { abs(Double($0) - mean) <= Double(tolerance) }
    }

    /// A fingertip over the lens with the torch on reads as a bright,
    /// strongly red frame. Anything else is the room.
    public static func isFingerCovering(meanRed: Double, meanGreen: Double, meanBlue: Double) -> Bool {
        meanRed > 90 && meanRed > meanGreen * 1.6 && meanRed > meanBlue * 1.6
    }
}

/// The measuring loop, kept pure so tests run exactly what ships. Estimates
/// every few frames for the live confidence, but records one into the
/// history only every half second. Back-to-back 8 s windows share almost
/// all their data, so recording each one made even noise look like it
/// agreed with itself.
public struct PulseTracker: Sendable {
    public static let acceptConfidence = 0.2
    public static let steadyConfidence = 0.35
    public static let historySize = 12
    /// Frames between estimates (the live redraw) and between recorded ones.
    public static let estimateEvery = 3
    public static let recordEvery = 15

    public private(set) var estimator: HeartRateEstimator
    public private(set) var history: [Int] = []
    public private(set) var confidence: Double = 0
    private var frames = 0

    public init(estimator: HeartRateEstimator = HeartRateEstimator(sampleRate: 30, windowSeconds: 8)) {
        self.estimator = estimator
    }

    public mutating func reset() {
        estimator.reset()
        history = []
        confidence = 0
        frames = 0
    }

    /// Returns true when a fresh estimate was made (time to redraw).
    @discardableResult
    public mutating func add(value: Double, at time: Double) -> Bool {
        estimator.add(value: value, at: time)
        frames += 1
        guard frames % PulseTracker.estimateEvery == 0 else { return false }
        guard let estimate = estimator.estimate() else { return true }
        confidence = estimate.confidence
        if frames % PulseTracker.recordEvery == 0 && estimate.confidence > PulseTracker.acceptConfidence {
            history.append(estimate.bpm)
            if history.count > PulseTracker.historySize { history.removeFirst() }
        }
        return true
    }

    /// The live number: the middle of the recorded estimates.
    public var bpm: Int? { HeartRateEstimator.median(history) }

    /// Six recorded estimates (three seconds) within ±3 bpm.
    public var isSteady: Bool {
        confidence >= PulseTracker.steadyConfidence && HeartRateEstimator.isSteady(history)
    }

    /// The number worth saving, or nil when the estimates never agreed.
    public var result: Int? {
        guard history.count >= 4, HeartRateEstimator.hasConsensus(history) else { return nil }
        return bpm
    }
}

public enum HeartbeatCopy {
    public static let disclaimer = "For curiosity, not for care. Heartbeat isn't a medical device; talk to a doctor about anything that worries you."

    public static func cardSummary(latest: HeartReading?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let latest else { return "Measure your pulse with the camera or a strap" }
        return "\(latest.bpm) bpm · \(CareCopy.relative(latest.at, now: now, calendar: calendar)) · \(latest.source.label.lowercased())"
    }

    /// Plain-language band for a resting reading.
    public static func band(bpm: Int) -> String {
        switch bpm {
        case ..<50: return "Low for resting"
        case 50..<60: return "Athlete range"
        case 60...100: return "Typical resting range"
        case 101...120: return "Elevated"
        default: return "High"
        }
    }

    public static func monthLine(_ month: HeartbeatMonth) -> String {
        guard let s = month.stats else { return "No readings yet this month." }
        let n = month.readings.count
        return "\(n) reading\(n == 1 ? "" : "s") · low \(s.min) · average \(s.avg) · high \(s.max)"
    }
}

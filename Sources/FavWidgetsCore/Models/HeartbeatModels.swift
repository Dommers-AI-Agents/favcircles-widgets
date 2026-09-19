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
/// Method: detrend against a one-second moving average (removes the slow
/// drift as the finger warms and the exposure settles), smooth lightly,
/// then autocorrelate the last window and pick the strongest lag between
/// 40 and 200 bpm. The normalized peak doubles as the confidence.
public struct HeartRateEstimator: Sendable {
    public struct Estimate: Equatable, Sendable {
        public let bpm: Int
        public let confidence: Double
    }

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
        guard isReady, values.count >= Int(sampleRate * 4) else { return nil }
        let signal = HeartRateEstimator.smooth(HeartRateEstimator.detrend(values, sampleRate: sampleRate), radius: 2)
        let n = signal.count
        let energy = signal.reduce(0) { $0 + $1 * $1 }
        guard energy > 0 else { return nil }
        let minLag = Int((60 / maxBPM) * sampleRate)
        let maxLag = min(n / 2, Int((60 / minBPM) * sampleRate))
        guard maxLag > minLag else { return nil }
        var bestLag = 0
        var best = -Double.infinity
        for lag in minLag...maxLag {
            var sum = 0.0
            for i in lag..<n { sum += signal[i] * signal[i - lag] }
            let r = sum / energy
            if r > best { best = r; bestLag = lag }
        }
        guard bestLag > 0 else { return nil }
        // Refine the peak with its neighbours for sub-sample lag.
        var lag = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            let rm = autocorr(signal, lag: bestLag - 1, energy: energy)
            let rp = autocorr(signal, lag: bestLag + 1, energy: energy)
            let denom = rm - 2 * best + rp
            if abs(denom) > 1e-9 { lag += 0.5 * (rm - rp) / denom }
        }
        let bpm = 60 * sampleRate / lag
        return Estimate(bpm: Int(bpm.rounded()), confidence: max(0, min(1, best)))
    }

    private func autocorr(_ s: [Double], lag: Int, energy: Double) -> Double {
        var sum = 0.0
        for i in lag..<s.count { sum += s[i] * s[i - lag] }
        return sum / energy
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

    static func smooth(_ x: [Double], radius: Int) -> [Double] {
        guard radius > 0 else { return x }
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - radius), hi = min(x.count - 1, i + radius)
            var sum = 0.0
            for j in lo...hi { sum += x[j] }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    /// A fingertip over the lens with the torch on reads as a bright,
    /// strongly red frame. Anything else is the room.
    public static func isFingerCovering(meanRed: Double, meanGreen: Double, meanBlue: Double) -> Bool {
        meanRed > 90 && meanRed > meanGreen * 1.6 && meanRed > meanBlue * 1.6
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

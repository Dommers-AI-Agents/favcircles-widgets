import Foundation

/// FavRun: turning GPS fixes into a run (Wes, 2026-10-06). Pure, so the
/// rules that decide distance, time and records are tested on a Mac.

/// One GPS reading.
public struct RunFix: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let time: Date
    /// Horizontal accuracy in meters (CLLocation.horizontalAccuracy); <0 = invalid.
    public let accuracy: Double

    public init(latitude: Double, longitude: Double, time: Date, accuracy: Double) {
        self.latitude = latitude; self.longitude = longitude; self.time = time; self.accuracy = accuracy
    }
}

/// A run in progress: distance from accepted fixes, moving time that stops
/// while paused, and the (distance, time) trail for splits and best efforts.
public struct RunTrack: Equatable, Sendable {
    /// Readings worse than this are ignored (indoors, start-up fixes).
    public static let maxAccuracy: Double = 25
    /// Faster than this between two fixes is a GPS jump, not running.
    public static let maxSpeed: Double = 12.5   // m/s, a 2:09 mile

    public private(set) var startedAt: Date
    public private(set) var distance: Double = 0          // meters
    public private(set) var points: [RunFix] = []         // accepted fixes, the route
    /// Cumulative (meters, moving seconds) at each accepted fix.
    public private(set) var samples: [RunSample] = []
    public private(set) var isPaused = false
    private var bankedSeconds: TimeInterval = 0
    private var activeSince: Date?
    private var lastFix: RunFix?          // last accepted fix of the current segment

    public init(startedAt: Date) {
        self.startedAt = startedAt
        self.activeSince = startedAt
    }

    public func movingSeconds(at now: Date) -> TimeInterval {
        bankedSeconds + (activeSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Adds a fix; returns whether it was used.
    @discardableResult
    public mutating func add(_ fix: RunFix) -> Bool {
        guard !isPaused, fix.accuracy >= 0, fix.accuracy <= Self.maxAccuracy, fix.time >= startedAt else { return false }
        if let last = lastFix {
            let meters = RunGeo.distance(last.latitude, last.longitude, fix.latitude, fix.longitude)
            let seconds = fix.time.timeIntervalSince(last.time)
            guard seconds > 0 else { return false }
            if meters / seconds > Self.maxSpeed { return false }
            // Standing still: jitter under the fix's own accuracy isn't distance
            if meters < min(fix.accuracy, last.accuracy) * 0.5 { return false }
            distance += meters
        }
        lastFix = fix
        points.append(fix)
        samples.append(RunSample(meters: distance, seconds: movingSeconds(at: fix.time)))
        return true
    }

    public mutating func pause(at now: Date) {
        guard !isPaused else { return }
        bankedSeconds = movingSeconds(at: now)
        activeSince = nil
        isPaused = true
    }

    /// Resuming starts a new segment: the gap walked while paused isn't counted.
    public mutating func resume(at now: Date) {
        guard isPaused else { return }
        activeSince = now
        isPaused = false
        lastFix = nil
    }
}

public struct RunSample: Equatable, Sendable, Codable {
    public let meters: Double
    public let seconds: Double
    public init(meters: Double, seconds: Double) { self.meters = meters; self.seconds = seconds }
}

public enum RunUnit: String, Codable, CaseIterable, Sendable {
    case miles = "mi", kilometers = "km"
    public var meters: Double { self == .miles ? 1609.344 : 1000 }
    public var label: String { rawValue }
    public static var localeDefault: RunUnit { Locale.current.measurementSystem == .us ? .miles : .kilometers }
}

public enum RunMath {
    /// Seconds per unit, or nil before there's enough distance to say.
    public static func pace(seconds: Double, meters: Double, unit: RunUnit) -> Double? {
        guard meters >= 20, seconds > 0 else { return nil }
        return seconds / (meters / unit.meters)
    }

    /// "8:42" (minutes:seconds), "—" when unknown.
    public static func paceText(_ secondsPerUnit: Double?) -> String {
        guard let s = secondsPerUnit, s.isFinite, s < 60 * 60 else { return "—" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "1:02:05" or "32:10".
    public static func clock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// "3.12"
    public static func distanceText(_ meters: Double, unit: RunUnit) -> String {
        String(format: "%.2f", meters / unit.meters)
    }

    /// Seconds each whole unit took (interpolated at the crossing).
    public static func splits(_ samples: [RunSample], unit: RunUnit) -> [Double] {
        var result: [Double] = []
        var next = unit.meters
        var lastBoundaryTime = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where b.meters > a.meters {
            while b.meters >= next {
                let f = (next - a.meters) / (b.meters - a.meters)
                let t = a.seconds + f * (b.seconds - a.seconds)
                result.append(t - lastBoundaryTime)
                lastBoundaryTime = t
                next += unit.meters
            }
        }
        return result
    }

    /// Fastest time over any stretch of `meters` (a best 1 mi / 5K inside a
    /// longer run), interpolated; nil if the run was shorter.
    public static func bestEffort(_ samples: [RunSample], meters target: Double) -> Double? {
        guard let total = samples.last?.meters, total >= target, samples.count > 1 else { return nil }
        func time(at m: Double) -> Double {
            // samples are monotone in meters
            var lo = 0, hi = samples.count - 1
            while hi - lo > 1 { let mid = (lo + hi) / 2; if samples[mid].meters < m { lo = mid } else { hi = mid } }
            let a = samples[lo], b = samples[hi]
            guard b.meters > a.meters else { return b.seconds }
            return a.seconds + (m - a.meters) / (b.meters - a.meters) * (b.seconds - a.seconds)
        }
        var best = Double.infinity
        for s in samples where s.meters + target <= total {
            best = min(best, time(at: s.meters + target) - s.seconds)
        }
        return best.isFinite ? best : nil
    }

    /// Estimated calories: about 1 kcal per kg per km, the usual running rule.
    public static func calories(meters: Double, weightKg: Double) -> Int {
        Int((meters / 1000 * weightKg * 1.036).rounded())
    }
}

public enum RunGeo {
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Douglas–Peucker, loosened until the route fits `maxPoints` (a route
    /// is stored in the month document, which has a size cap).
    public static func simplify(_ pts: [(Double, Double)], maxPoints: Int = 600) -> [(Double, Double)] {
        guard pts.count > maxPoints else { return pts }
        var tolerance = 3.0
        var out = pts
        while out.count > maxPoints && tolerance < 500 {
            out = douglasPeucker(pts, tolerance: tolerance)
            tolerance *= 1.6
        }
        return out
    }

    private static func douglasPeucker(_ pts: [(Double, Double)], tolerance: Double) -> [(Double, Double)] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (s, e) = stack.popLast() {
            var maxD = 0.0, idx = s
            for i in (s + 1)..<e {
                let d = perpendicular(pts[i], pts[s], pts[e])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > tolerance { keep[idx] = true; stack.append((s, idx)); stack.append((idx, e)) }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    /// Distance in meters from p to the segment a–b (local flat projection).
    private static func perpendicular(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let k = 111_320.0, c = cos(a.0 * .pi / 180)
        let (px, py) = ((p.1 - a.1) * k * c, (p.0 - a.0) * k)
        let (bx, by) = ((b.1 - a.1) * k * c, (b.0 - a.0) * k)
        let len2 = bx * bx + by * by
        guard len2 > 0 else { return (px * px + py * py).squareRoot() }
        let t = max(0, min(1, (px * bx + py * by) / len2))
        let (dx, dy) = (px - t * bx, py - t * by)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Google encoded-polyline (1e5): a 10 km route in about 2 KB.
    public static func encode(_ pts: [(Double, Double)]) -> String {
        var out = ""; var lastLat = 0, lastLon = 0
        func put(_ v: Int) {
            var v = v < 0 ? ~(v << 1) : (v << 1)
            while v >= 0x20 { out.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63))); v >>= 5 }
            out.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for (lat, lon) in pts {
            let la = Int((lat * 1e5).rounded()), lo = Int((lon * 1e5).rounded())
            put(la - lastLat); put(lo - lastLon); lastLat = la; lastLon = lo
        }
        return out
    }

    public static func decode(_ s: String) -> [(Double, Double)] {
        var pts: [(Double, Double)] = []
        let bytes = Array(s.utf8); var i = 0; var lat = 0, lon = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63; i += 1
                result |= (b & 0x1f) << shift; shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count, let dl = next(), let dn = next() {
            lat += dl; lon += dn
            pts.append((Double(lat) / 1e5, Double(lon) / 1e5))
        }
        return pts
    }
}

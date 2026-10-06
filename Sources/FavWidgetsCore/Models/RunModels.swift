import Foundation

/// FavRun documents: settings (single) + runs by month (never pruned).

public struct RunSettings: WidgetModel {
    public static let schemaVersion = 1
    public var unit: RunUnit
    /// For the calorie estimate; nil = 70 kg.
    public var weightKg: Double?

    public init(unit: RunUnit = .localeDefault, weightKg: Double? = nil) {
        self.unit = unit; self.weightKg = weightKg
    }
    public static let empty = RunSettings()
}

public struct RunRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let movingSeconds: Double
    public let distanceMeters: Double
    /// Encoded polyline of the (simplified) route.
    public let route: String
    /// Seconds per mile AND per km, so either unit shows true splits.
    public let splitsMile: [Double]
    public let splitsKm: [Double]
    /// Fastest stretch inside this run: "1k", "1mi", "5k", "10k", "half" → seconds.
    public let efforts: [String: Double]
    public let calories: Int
    public var title: String?

    public init(id: String = UUID().uuidString, startedAt: Date, endedAt: Date, movingSeconds: Double, distanceMeters: Double,
                route: String, splitsMile: [Double], splitsKm: [Double], efforts: [String: Double], calories: Int, title: String? = nil) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt; self.movingSeconds = movingSeconds
        self.distanceMeters = distanceMeters; self.route = route; self.splitsMile = splitsMile; self.splitsKm = splitsKm
        self.efforts = efforts; self.calories = calories; self.title = title
    }

    public func splits(_ unit: RunUnit) -> [Double] { unit == .miles ? splitsMile : splitsKm }
    public func pace(_ unit: RunUnit) -> Double? { RunMath.pace(seconds: movingSeconds, meters: distanceMeters, unit: unit) }
    public var coordinates: [(Double, Double)] { RunGeo.decode(route) }

    /// Distances best efforts are kept for.
    public static let effortDistances: [(key: String, label: String, meters: Double)] = [
        ("1k", "1K", 1000), ("1mi", "1 mile", 1609.344), ("5k", "5K", 5000), ("10k", "10K", 10000), ("half", "Half marathon", 21097.5)
    ]

    /// Builds the saved run from a finished track.
    public static func from(_ track: RunTrack, endedAt: Date, weightKg: Double?) -> RunRecord {
        let samples = track.samples
        var efforts: [String: Double] = [:]
        for e in effortDistances { if let s = RunMath.bestEffort(samples, meters: e.meters) { efforts[e.key] = s } }
        let route = RunGeo.encode(RunGeo.simplify(track.points.map { ($0.latitude, $0.longitude) }))
        return RunRecord(startedAt: track.startedAt, endedAt: endedAt, movingSeconds: track.movingSeconds(at: endedAt),
                         distanceMeters: track.distance, route: route,
                         splitsMile: RunMath.splits(samples, unit: .miles), splitsKm: RunMath.splits(samples, unit: .kilometers),
                         efforts: efforts, calories: RunMath.calories(meters: track.distance, weightKg: weightKg ?? 70))
    }
}

public struct RunMonth: WidgetModel {
    public var runs: [RunRecord]
    public init(runs: [RunRecord] = []) { self.runs = runs }
    public static let empty = RunMonth()

    /// Runs only ever get added: keep both sides'.
    public static func merge(local: RunMonth, remote: RunMonth) -> RunMonth {
        let known = Set(local.runs.map(\.id))
        var merged = local
        merged.runs.append(contentsOf: remote.runs.filter { !known.contains($0.id) })
        merged.runs.sort { $0.startedAt > $1.startedAt }
        return merged
    }
}

/// Personal records across all loaded runs.
public enum RunRecords {
    public struct Best: Equatable { public let label: String; public let seconds: Double; public let runId: String }

    public static func bests(_ runs: [RunRecord]) -> [Best] {
        RunRecord.effortDistances.compactMap { e in
            let best = runs.compactMap { r in r.efforts[e.key].map { (r.id, $0) } }.min { $0.1 < $1.1 }
            return best.map { Best(label: e.label, seconds: $0.1, runId: $0.0) }
        }
    }

    public static func longest(_ runs: [RunRecord]) -> RunRecord? { runs.max { $0.distanceMeters < $1.distanceMeters } }
}

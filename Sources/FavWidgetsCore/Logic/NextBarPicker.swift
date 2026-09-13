import Foundation

/// Picks the next bar: random, but weighted toward what's close. A bar a
/// block away is far more likely than one across town, and the last few
/// suggestions are skipped so "Shuffle" feels fresh.
public enum NextBarPicker {
    public struct Scored: Equatable, Sendable {
        public let candidate: WidgetPlaceCandidate
        public let distanceMeters: Double
    }

    /// Candidates within `maxDistance` of `origin` (all of them when the
    /// origin is unknown), nearest first.
    public static func pool(
        _ candidates: [WidgetPlaceCandidate],
        origin: WidgetCoordinate?,
        maxDistanceMeters: Double,
        sources: Set<WidgetPlaceSource>
    ) -> [Scored] {
        var seen = Set<String>()
        var scored: [Scored] = []
        for candidate in candidates where sources.contains(candidate.source) {
            // The same venue saved by several people shows once; the first
            // (nearest, since the app sorts by distance) copy wins.
            let key = candidate.name.lowercased() + "|" + String(format: "%.4f,%.4f", candidate.coordinate.latitude, candidate.coordinate.longitude)
            guard !seen.contains(key) else { continue }
            let distance = origin.map { $0.distance(to: candidate.coordinate) } ?? 0
            guard origin == nil || distance <= maxDistanceMeters else { continue }
            seen.insert(key)
            scored.append(Scored(candidate: candidate, distanceMeters: distance))
        }
        return scored.sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// Weight ∝ 1 / (distance + 300 m)²: the nearest few dominate without
    /// making anything impossible.
    public static func weight(distanceMeters: Double) -> Double {
        let d = max(0, distanceMeters) + 300
        return 1 / (d * d)
    }

    /// One weighted-random pick, avoiding `excluding` when anything else is
    /// available. `random` is injectable for tests (0 ..< 1).
    public static func pick(
        from pool: [Scored],
        excluding: [String],
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Scored? {
        guard !pool.isEmpty else { return nil }
        let fresh = pool.filter { !excluding.contains($0.candidate.id) }
        let choices = fresh.isEmpty ? pool : fresh
        let weights = choices.map { weight(distanceMeters: $0.distanceMeters) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return choices.first }
        var target = random() * total
        for (index, w) in weights.enumerated() {
            target -= w
            if target < 0 { return choices[index] }
        }
        return choices.last
    }
}

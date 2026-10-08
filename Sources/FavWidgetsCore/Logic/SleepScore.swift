import Foundation

/// The 0–100 score, labels, trends, and turning Health samples into nights.
public enum SleepScore {
    public struct Breakdown: Equatable, Sendable {
        public let total: Int
        public let duration: Int
        public let efficiency: Int
        public let consistency: Int
        public let stages: Int?
    }

    /// Duration 50 · efficiency 20 · consistency 20 · deep+REM 10. Without
    /// stage data the other three are scaled up to 100.
    public static func score(_ night: SleepNight, goalHours: Double, recentBedtimes: [Date], calendar: Calendar = .current) -> Breakdown {
        let goal = max(goalHours, 4) * 60
        let asleep = Double(night.asleepMinutes)
        // Full marks within 30 min under goal; oversleeping 2h+ past goal loses a little
        let durationFrac: Double = asleep >= goal - 30
            ? (asleep > goal + 120 ? 0.85 : 1)
            : max(0, asleep / (goal - 30))
        let efficiencyFrac = min(1, max(0, asleep / Double(night.inBedMinutes) - 0.65) / 0.25) // 65% → 0, 90%+ → 1
        let consistencyFrac: Double = {
            guard let median = medianBedtimeMinutes(recentBedtimes, calendar: calendar) else { return 1 }
            let diff = abs(Double(bedtimeMinutes(night.bedtime, calendar: calendar) - median))
            return diff <= 45 ? 1 : max(0, 1 - (diff - 45) / 120)
        }()
        var stages: Double?
        if let deep = night.deepMinutes, let rem = night.remMinutes, asleep > 0 {
            // ~13–23% deep and ~20–25% REM are typical; together ≥ 35% = full
            stages = min(1, Double(deep + rem) / asleep / 0.35)
        }
        let d = durationFrac * 50, e = efficiencyFrac * 20, c = consistencyFrac * 20
        let total: Double
        if let s = stages { total = d + e + c + s * 10 } else { total = (d + e + c) / 90 * 100 }
        return Breakdown(total: Int(total.rounded()), duration: Int(d.rounded()), efficiency: Int(e.rounded()),
                         consistency: Int(c.rounded()), stages: stages.map { Int(($0 * 10).rounded()) })
    }

    public static func label(_ score: Int) -> String {
        switch score {
        case 85...: return "Great"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default: return "Poor"
        }
    }

    /// Bedtime as minutes from noon-to-noon, so 11 PM and 1 AM are close (660 vs 780).
    public static func bedtimeMinutes(_ date: Date, calendar: Calendar = .current) -> Int {
        let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return m < 12 * 60 ? m + 12 * 60 : m - 12 * 60
    }

    public static func medianBedtimeMinutes(_ dates: [Date], calendar: Calendar = .current) -> Int? {
        let values = dates.map { bedtimeMinutes($0, calendar: calendar) }.sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    /// "50 min later than usual" / nil when within 20 min
    public static func bedtimeNote(_ night: SleepNight, recentBedtimes: [Date], calendar: Calendar = .current) -> String? {
        guard let median = medianBedtimeMinutes(recentBedtimes, calendar: calendar) else { return nil }
        let diff = bedtimeMinutes(night.bedtime, calendar: calendar) - median
        guard abs(diff) >= 20 else { return nil }
        let amount = abs(diff) >= 60 ? "\(abs(diff) / 60)h \(abs(diff) % 60)m" : "\(abs(diff)) min"
        return "To bed \(amount) \(diff > 0 ? "later" : "earlier") than usual"
    }

    /// "7h 12m"
    public static func durationText(_ minutes: Int) -> String { "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" }

    /// Average asleep minutes over the nights, nil when none.
    public static func averageMinutes(_ nights: [SleepNight]) -> Int? {
        nights.isEmpty ? nil : nights.map(\.asleepMinutes).reduce(0, +) / nights.count
    }

    /// Health samples → one night per wake day. A night runs noon to noon;
    /// sessions with a gap under 90 min are the same night. Stage minutes
    /// only when the samples carry stages (Watch); "asleep" alone = iPhone.
    public static func nights(from samples: [SleepSample], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = samples.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var groups: [[SleepSample]] = []
        for s in sorted {
            if var last = groups.last, let lastEnd = last.map(\.end).max(), s.start.timeIntervalSince(lastEnd) < 90 * 60 {
                last.append(s); groups[groups.count - 1] = last
            } else {
                groups.append([s])
            }
        }
        var byDay: [DayKey: SleepNight] = [:]
        for g in groups {
            let asleepStages: [SleepSample.Stage] = [.core, .deep, .rem, .asleep]
            let sleeping = g.filter { asleepStages.contains($0.stage) }
            guard let first = sleeping.map(\.start).min(), let last = sleeping.map(\.end).max() else { continue }
            let bed = min(first, g.filter { $0.stage == .inBed }.map(\.start).min() ?? first)
            let wake = max(last, g.filter { $0.stage == .inBed }.map(\.end).max() ?? last)
            func minutes(_ stages: [SleepSample.Stage]) -> Int {
                Int(merged(g.filter { stages.contains($0.stage) }) / 60)
            }
            let asleep = minutes(asleepStages)
            guard asleep >= 60 else { continue }  // naps and noise
            let hasStages = g.contains { $0.stage == .deep || $0.stage == .rem }
            let night = SleepNight(day: DayKey(wake, calendar: calendar), bedtime: bed, wakeTime: wake,
                                   asleepMinutes: asleep, awakeMinutes: minutes([.awake]),
                                   deepMinutes: hasStages ? minutes([.deep]) : nil,
                                   remMinutes: hasStages ? minutes([.rem]) : nil,
                                   coreMinutes: hasStages ? minutes([.core]) : nil, source: .health)
            // Two sessions waking the same day: keep the longer
            if let existing = byDay[night.day], existing.asleepMinutes >= night.asleepMinutes { continue }
            byDay[night.day] = night
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Total seconds covered by the samples, overlaps counted once
    /// (an iPhone and a Watch both recording the same night).
    static func merged(_ samples: [SleepSample]) -> TimeInterval {
        let sorted = samples.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for s in sorted {
            if let c = current, s.start <= c.1 {
                current = (c.0, max(c.1, s.end))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = (s.start, s.end)
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }
}

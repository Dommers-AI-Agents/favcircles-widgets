import Foundation

/// Calories and units for cardio, kept out of the views so the numbers
/// can be checked on a Mac.
public enum WorkoutCardioLogic {
    /// Metabolic equivalents by machine and effort (Compendium of Physical
    /// Activities, rounded). Rough by nature: the machine's own display
    /// wins when the person types it in.
    public static func met(kind: CardioKind, intensity: CardioIntensity) -> Double {
        switch (kind, intensity) {
        case (.treadmill, .easy), (.walk, .easy): return 3.5
        case (.treadmill, .moderate), (.walk, .moderate): return 5.0
        case (.treadmill, .hard), (.walk, .hard): return 8.0
        case (.run, .easy): return 7.0
        case (.run, .moderate): return 9.8
        case (.run, .hard): return 11.5
        case (.stepper, .easy): return 5.0
        case (.stepper, .moderate): return 7.0
        case (.stepper, .hard): return 9.0
        case (.cycle, .easy): return 4.0
        case (.cycle, .moderate): return 6.8
        case (.cycle, .hard): return 10.0
        case (.elliptical, .easy): return 4.0
        case (.elliptical, .moderate): return 5.5
        case (.elliptical, .hard): return 8.0
        case (.rower, .easy): return 4.8
        case (.rower, .moderate): return 7.0
        case (.rower, .hard): return 10.0
        }
    }

    /// kcal ≈ MET × kg × hours. Nil without a body weight.
    public static func estimatedCalories(kind: CardioKind, intensity: CardioIntensity, minutes: Int, weightKg: Double?) -> Int? {
        guard let weightKg, weightKg > 0, minutes > 0 else { return nil }
        return Int((met(kind: kind, intensity: intensity) * weightKg * Double(minutes) / 60).rounded())
    }

    /// The calories to show for an entry: typed if present, else estimated.
    public static func calories(for entry: CardioEntry, weightKg: Double?) -> Int? {
        entry.calories ?? estimatedCalories(kind: entry.kind, intensity: entry.intensity, minutes: entry.minutes, weightKg: weightKg)
    }

    public static func totalCalories(_ entries: [CardioEntry], weightKg: Double?) -> Int {
        entries.filter(\.holdsUserData).compactMap { calories(for: $0, weightKg: weightKg) }.reduce(0, +)
    }

    // MARK: Units

    public static func kg(fromLb lb: Double) -> Double { lb * 0.45359237 }
    public static func lb(fromKg kg: Double) -> Double { kg / 0.45359237 }
    public static func cm(feet: Int, inches: Double) -> Double { (Double(feet) * 12 + inches) * 2.54 }
    public static func feetInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = (cm / 2.54).rounded()
        return (Int(totalInches) / 12, Int(totalInches) % 12)
    }

    /// "5′11″" or "180 cm".
    public static func heightText(_ cm: Double?, unit: WeightUnit) -> String? {
        guard let cm else { return nil }
        if unit == .kg { return "\(Int(cm.rounded())) cm" }
        let (f, i) = feetInches(fromCm: cm)
        return "\(f)′\(i)″"
    }

    /// "172 lb" or "78 kg".
    public static func weightText(_ kg: Double?, unit: WeightUnit) -> String? {
        guard let kg else { return nil }
        return unit == .kg ? "\(Int(kg.rounded())) kg" : "\(Int(lb(fromKg: kg).rounded())) lb"
    }

    /// "20 min · 1.5 mi · 210 kcal"
    public static func line(for entry: CardioEntry, distanceUnit: String, weightKg: Double?) -> String {
        var parts = ["\(entry.minutes) min"]
        if let d = entry.distance, d > 0 { parts.append("\(d.formatted(.number.precision(.fractionLength(0...2)))) \(distanceUnit)") }
        if let kcal = calories(for: entry, weightKg: weightKg) { parts.append("\(kcal) kcal" + (entry.calories == nil ? " est." : "")) }
        return parts.joined(separator: " · ")
    }
}

/// What a finished workout says about itself: the summary sheet, the
/// share text, and the Inner Circle post all come from here.
public struct WorkoutShareSummary: Codable, Equatable, Sendable {
    public struct ExerciseLine: Codable, Equatable, Sendable {
        public var name: String
        public var sets: Int
        public var bestSet: String
        public var isPR: Bool
        public init(name: String, sets: Int, bestSet: String, isPR: Bool) {
            self.name = name
            self.sets = sets
            self.bestSet = bestSet
            self.isPR = isPR
        }
    }
    public struct CardioLine: Codable, Equatable, Sendable {
        public var name: String
        public var minutes: Int
        public var detail: String
        public init(name: String, minutes: Int, detail: String) {
            self.name = name
            self.minutes = minutes
            self.detail = detail
        }
    }

    public var name: String
    public var startedAt: Date
    public var durationSeconds: Int
    public var completedSets: Int
    public var exercises: [ExerciseLine]
    public var cardio: [CardioLine]
    public var prCount: Int
    public var unit: String

    public init(name: String, startedAt: Date, durationSeconds: Int, completedSets: Int, exercises: [ExerciseLine], cardio: [CardioLine], prCount: Int, unit: String) {
        self.name = name
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.completedSets = completedSets
        self.exercises = exercises
        self.cardio = cardio
        self.prCount = prCount
        self.unit = unit
    }

    public var cardioMinutes: Int { cardio.reduce(0) { $0 + $1.minutes } }

    /// Builds the summary from a finished session. `exerciseName` resolves
    /// custom names that live only on this device.
    public static func make(session: WorkoutSession, newRecords: [String: PersonalRecord], unit: WeightUnit, weightKg: Double?,
                            exerciseName: (String) -> String) -> WorkoutShareSummary {
        let ids = WorkoutSessionLogic.orderedExerciseIds(in: session)
        let lines: [ExerciseLine] = ids.compactMap { id in
            let done = session.sets.filter { $0.exerciseId == id && $0.completedAt != nil && !$0.isWarmup }
            let counted = done.isEmpty ? session.sets.filter { $0.exerciseId == id && WorkoutSessionLogic.holdsUserData($0) } : done
            guard !counted.isEmpty else { return nil }
            let best = counted.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }!
            let bestText = best.weight > 0 ? "\(trim(best.weight)) \(unit.label) × \(best.reps)" : "\(best.reps) reps"
            return ExerciseLine(name: exerciseName(id), sets: counted.count, bestSet: bestText, isPR: newRecords[id] != nil)
        }
        let distanceUnit = unit == .kg ? "km" : "mi"
        let cardio = session.cardio.filter(\.holdsUserData).map {
            CardioLine(name: $0.kind.name, minutes: $0.minutes, detail: WorkoutCardioLogic.line(for: $0, distanceUnit: distanceUnit, weightKg: weightKg))
        }
        return WorkoutShareSummary(
            name: session.name,
            startedAt: session.startedAt,
            durationSeconds: Int(WorkoutSessionLogic.duration(of: session)),
            completedSets: WorkoutSessionLogic.completedSetCount(session),
            exercises: lines,
            cardio: cardio,
            prCount: newRecords.count,
            unit: unit.label
        )
    }

    /// The text that goes to the share sheet.
    public func shareText(calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateStyle = .medium
        f.timeStyle = .none
        var lines = ["\(name) · \(f.string(from: startedAt))"]
        let minutes = max(1, durationSeconds / 60)
        var headline = "\(minutes) min"
        if !exercises.isEmpty { headline += " · \(exercises.count) exercise\(exercises.count == 1 ? "" : "s") · \(completedSets) sets" }
        if cardioMinutes > 0 { headline += " · \(cardioMinutes) min cardio" }
        if prCount > 0 { headline += " · \(prCount) PR\(prCount == 1 ? "" : "s")" }
        lines.append(headline)
        for e in exercises { lines.append("• \(e.name): \(e.bestSet)\(e.isPR ? " 🏆" : "") (\(e.sets) set\(e.sets == 1 ? "" : "s"))") }
        for c in cardio { lines.append("• \(c.name): \(c.detail)") }
        lines.append("Logged with FavCircles")
        return lines.joined(separator: "\n")
    }

    private static func trim(_ value: Double) -> String { WorkoutNumber.trim(value) }
}

/// "135", "137.5": a weight written the way a person would write it, with
/// no trailing zeros. One copy, shared by the share text, the routine
/// summary and the set rows.
public enum WorkoutNumber {
    public static func trim(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : rounded.formatted(.number.precision(.fractionLength(0...2)))
    }
}

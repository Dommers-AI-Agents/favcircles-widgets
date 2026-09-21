import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg, lb

    public var label: String { rawValue }
}

public struct Exercise: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var muscleGroup: String
    /// A photo the user attached (the machine's placard, say). Built-in
    /// exercises get theirs from `WorkoutSettings.exerciseImages`.
    public var imageUrl: String?

    public init(id: String = UUID().uuidString, name: String, muscleGroup: String, imageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.imageUrl = imageUrl
    }

    /// SF Symbol stand-in when there is no photo.
    public var symbolName: String {
        switch muscleGroup.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.step.training"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "cardio": return "figure.run"
        default: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Cardio

public struct RoutineItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var exerciseId: String
    public var targetSets: Int
    public var targetReps: Int
    /// What you lifted last time. Shown as the row's placeholder so a
    /// repeat workout is all ticks and no typing. Absent on routines
    /// written before the weight was remembered (0 is "no idea yet").
    public var targetWeight: Double?

    public init(id: UUID = UUID(), exerciseId: String, targetSets: Int = 3, targetReps: Int = 10, targetWeight: Double? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
    }
}

public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [RoutineItem]

    public init(id: UUID = UUID(), name: String, items: [RoutineItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public struct SetEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var exerciseId: String
    public var reps: Int
    public var weight: Double
    public var isWarmup: Bool
    public var completedAt: Date?

    public init(id: UUID = UUID(), exerciseId: String, reps: Int, weight: Double, isWarmup: Bool = false, completedAt: Date? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.reps = reps
        self.weight = weight
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }
}

public struct WorkoutSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var routineId: UUID?
    public var name: String
    public var startedAt: Date
    public var endedAt: Date?
    public var sets: [SetEntry]
    public var cardio: [CardioEntry]
    public var notes: String?

    public init(id: UUID = UUID(), routineId: UUID? = nil, name: String, startedAt: Date = Date(),
                endedAt: Date? = nil, sets: [SetEntry] = [], cardio: [CardioEntry] = [], notes: String? = nil) {
        self.id = id
        self.routineId = routineId
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
        self.cardio = cardio
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, routineId, name, startedAt, endedAt, sets, cardio, notes }

    /// Sessions stored before cardio existed decode with none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        routineId = try c.decodeIfPresent(UUID.self, forKey: .routineId)
        name = try c.decode(String.self, forKey: .name)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        sets = try c.decodeIfPresent([SetEntry].self, forKey: .sets) ?? []
        cardio = try c.decodeIfPresent([CardioEntry].self, forKey: .cardio) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public var isActive: Bool { endedAt == nil }

    public var cardioMinutes: Int { cardio.filter(\.holdsUserData).reduce(0) { $0 + $1.minutes } }
    public var exerciseCount: Int { Set(sets.filter { $0.completedAt != nil || $0.weight > 0 || $0.reps > 0 }.map(\.exerciseId)).count }

    public var totalVolume: Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

/// Best lift per exercise, kept as a running record so PR detection never
/// scans history.
public struct PersonalRecord: Codable, Equatable, Sendable {
    public var weight: Double
    public var reps: Int
    public var estimatedOneRM: Double
    public var date: Date
    public var sessionId: UUID

    public init(weight: Double, reps: Int, estimatedOneRM: Double, date: Date, sessionId: UUID) {
        self.weight = weight
        self.reps = reps
        self.estimatedOneRM = estimatedOneRM
        self.date = date
        self.sessionId = sessionId
    }
}

/// A routine and the workout that just diverged from it: what the routine
/// would become if the person says yes.
public struct RoutineUpdate: Equatable, Sendable {
    public let routine: Routine
    /// True when the routine came from the starter list and saying yes
    /// saves the person their own copy for the first time.
    public let isNew: Bool
    /// One line per change, in the words the sheet shows.
    public let changes: [String]

    public init(routine: Routine, isNew: Bool, changes: [String]) {
        self.routine = routine
        self.isNew = isNew
        self.changes = changes
    }
}

/// What "Finish workout" hands back for the summary sheet.
public struct WorkoutSummary: Identifiable {
    public let id = UUID()
    public let name: String
    public let duration: TimeInterval
    public let completedSets: Int
    public let unit: WeightUnit
    public let newRecords: [(id: String, exercise: String, record: PersonalRecord)]
    /// Best sets, cardio and PR count: the summary sheet, the share text
    /// and the Inner Circle post all read from this.
    public let share: WorkoutShareSummary
    /// Set when the workout differed from the routine it started from, so
    /// the sheet can offer to keep the change.
    public let routineUpdate: RoutineUpdate?

    public init(name: String, duration: TimeInterval, completedSets: Int, unit: WeightUnit,
                newRecords: [(id: String, exercise: String, record: PersonalRecord)], share: WorkoutShareSummary,
                routineUpdate: RoutineUpdate? = nil) {
        self.name = name
        self.duration = duration
        self.completedSets = completedSets
        self.unit = unit
        self.newRecords = newRecords
        self.share = share
        self.routineUpdate = routineUpdate
    }
}

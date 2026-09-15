import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg, lb

    public var label: String { rawValue }
}

public struct Exercise: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var muscleGroup: String

    public init(id: String = UUID().uuidString, name: String, muscleGroup: String) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
    }
}

public struct RoutineItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var exerciseId: String
    public var targetSets: Int
    public var targetReps: Int

    public init(id: UUID = UUID(), exerciseId: String, targetSets: Int = 3, targetReps: Int = 10) {
        self.id = id
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetReps = targetReps
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
    public var notes: String?

    public init(id: UUID = UUID(), routineId: UUID? = nil, name: String, startedAt: Date = Date(),
                endedAt: Date? = nil, sets: [SetEntry] = [], notes: String? = nil) {
        self.id = id
        self.routineId = routineId
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
        self.notes = notes
    }

    public var isActive: Bool { endedAt == nil }

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

/// Settings document (`workouts`): unit, custom exercises, routines, PRs.
/// The built-in exercise catalog lives in code (`ExerciseCatalog`) so it is
/// never stored per user.
public struct WorkoutSettings: WidgetModel {
    public var unit: WeightUnit
    public var restTimerSeconds: Int
    /// Start the rest countdown automatically when a set is ticked. Off =
    /// no timer at all; the length above is kept for when it's turned back on.
    public var autoRestTimer: Bool
    public var customExercises: [Exercise]
    public var routines: [Routine]
    public var prsByExercise: [String: PersonalRecord]
    /// A workout in progress survives app relaunches here, then moves into
    /// its month document when finished.
    public var activeSession: WorkoutSession?

    public init(unit: WeightUnit = .lb, restTimerSeconds: Int = 90, autoRestTimer: Bool = true, customExercises: [Exercise] = [],
                routines: [Routine] = [], prsByExercise: [String: PersonalRecord] = [:], activeSession: WorkoutSession? = nil) {
        self.unit = unit
        self.restTimerSeconds = restTimerSeconds
        self.autoRestTimer = autoRestTimer
        self.customExercises = customExercises
        self.routines = routines
        self.prsByExercise = prsByExercise
        self.activeSession = activeSession
    }

    private enum CodingKeys: String, CodingKey {
        case unit, restTimerSeconds, autoRestTimer, customExercises, routines, prsByExercise, activeSession
    }

    /// Documents written before a field existed decode with that field's
    /// default instead of failing (a synthesized decoder would throw on the
    /// missing key and lose the user's settings).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = try c.decodeIfPresent(WeightUnit.self, forKey: .unit) ?? .lb
        restTimerSeconds = try c.decodeIfPresent(Int.self, forKey: .restTimerSeconds) ?? 90
        autoRestTimer = try c.decodeIfPresent(Bool.self, forKey: .autoRestTimer) ?? true
        customExercises = try c.decodeIfPresent([Exercise].self, forKey: .customExercises) ?? []
        routines = try c.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        prsByExercise = try c.decodeIfPresent([String: PersonalRecord].self, forKey: .prsByExercise) ?? [:]
        activeSession = try c.decodeIfPresent(WorkoutSession.self, forKey: .activeSession)
    }

    public static let empty = WorkoutSettings()

    public var allExercises: [Exercise] { ExerciseCatalog.builtIn + customExercises }

    public func exercise(id: String) -> Exercise? {
        allExercises.first { $0.id == id }
    }
}

/// One month of finished sessions (`workouts_yyyy-MM`).
public struct WorkoutMonth: WidgetModel {
    public var sessions: [WorkoutSession]

    public init(sessions: [WorkoutSession] = []) {
        self.sessions = sessions
    }

    public static let empty = WorkoutMonth()

    public static func merge(local: WorkoutMonth, remote: WorkoutMonth) -> WorkoutMonth {
        let known = Set(local.sessions.map(\.id))
        var merged = local
        merged.sessions.append(contentsOf: remote.sessions.filter { !known.contains($0.id) })
        merged.sessions.sort { $0.startedAt < $1.startedAt }
        return merged
    }
}

/// Built-in exercises. Ids are stable strings so logs and PRs survive
/// renames.
public enum ExerciseCatalog {
    public static let builtIn: [Exercise] = [
        Exercise(id: "bench_press", name: "Bench Press", muscleGroup: "Chest"),
        Exercise(id: "incline_db_press", name: "Incline Dumbbell Press", muscleGroup: "Chest"),
        Exercise(id: "push_up", name: "Push-Up", muscleGroup: "Chest"),
        Exercise(id: "squat", name: "Squat", muscleGroup: "Legs"),
        Exercise(id: "leg_press", name: "Leg Press", muscleGroup: "Legs"),
        Exercise(id: "lunge", name: "Lunge", muscleGroup: "Legs"),
        Exercise(id: "romanian_deadlift", name: "Romanian Deadlift", muscleGroup: "Legs"),
        Exercise(id: "deadlift", name: "Deadlift", muscleGroup: "Back"),
        Exercise(id: "barbell_row", name: "Barbell Row", muscleGroup: "Back"),
        Exercise(id: "lat_pulldown", name: "Lat Pulldown", muscleGroup: "Back"),
        Exercise(id: "pull_up", name: "Pull-Up", muscleGroup: "Back"),
        Exercise(id: "overhead_press", name: "Overhead Press", muscleGroup: "Shoulders"),
        Exercise(id: "lateral_raise", name: "Lateral Raise", muscleGroup: "Shoulders"),
        Exercise(id: "bicep_curl", name: "Bicep Curl", muscleGroup: "Arms"),
        Exercise(id: "tricep_pushdown", name: "Tricep Pushdown", muscleGroup: "Arms"),
        Exercise(id: "plank", name: "Plank", muscleGroup: "Core"),
        Exercise(id: "hanging_leg_raise", name: "Hanging Leg Raise", muscleGroup: "Core")
    ]

    /// Starter routines offered until the user makes their own.
    public static let starterRoutines: [Routine] = [
        Routine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Push", items: [
            RoutineItem(exerciseId: "bench_press", targetSets: 4, targetReps: 8),
            RoutineItem(exerciseId: "overhead_press", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "incline_db_press", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "tricep_pushdown", targetSets: 3, targetReps: 12)
        ]),
        Routine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Pull", items: [
            RoutineItem(exerciseId: "deadlift", targetSets: 3, targetReps: 5),
            RoutineItem(exerciseId: "barbell_row", targetSets: 4, targetReps: 8),
            RoutineItem(exerciseId: "lat_pulldown", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "bicep_curl", targetSets: 3, targetReps: 12)
        ]),
        Routine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Legs", items: [
            RoutineItem(exerciseId: "squat", targetSets: 4, targetReps: 8),
            RoutineItem(exerciseId: "romanian_deadlift", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "leg_press", targetSets: 3, targetReps: 12),
            RoutineItem(exerciseId: "lunge", targetSets: 3, targetReps: 12)
        ])
    ]
}

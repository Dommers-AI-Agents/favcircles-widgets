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

public enum CardioKind: String, Codable, CaseIterable, Sendable {
    case treadmill, stepper, cycle, elliptical, rower, walk, run

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardioKind(rawValue: raw) ?? .treadmill
    }

    public var name: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .stepper: return "Stepper"
        case .cycle: return "Cycle"
        case .elliptical: return "Elliptical"
        case .rower: return "Rower"
        case .walk: return "Walk"
        case .run: return "Run"
        }
    }

    public var symbolName: String {
        switch self {
        case .treadmill, .run: return "figure.run"
        case .stepper: return "figure.stairs"
        case .cycle: return "figure.outdoor.cycle"
        case .elliptical: return "figure.elliptical"
        case .rower: return "figure.rower"
        case .walk: return "figure.walk"
        }
    }

    /// Whether distance makes sense for this machine.
    public var tracksDistance: Bool { self != .stepper }
}

public enum CardioIntensity: String, Codable, CaseIterable, Sendable {
    case easy, moderate, hard

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardioIntensity(rawValue: raw) ?? .moderate
    }

    public var label: String { rawValue.capitalized }
}

/// One stretch on a machine, alongside the sets.
public struct CardioEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: CardioKind
    public var minutes: Int
    /// In the session's distance unit (mi when lifting in lb, km in kg).
    public var distance: Double?
    public var intensity: CardioIntensity
    /// Typed from the machine's display, or estimated from the profile.
    public var calories: Int?
    public var completedAt: Date?

    public init(id: UUID = UUID(), kind: CardioKind, minutes: Int = 0, distance: Double? = nil,
                intensity: CardioIntensity = .moderate, calories: Int? = nil, completedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
        self.distance = distance
        self.intensity = intensity
        self.calories = calories
        self.completedAt = completedAt
    }

    public var holdsUserData: Bool { completedAt != nil || minutes > 0 || (distance ?? 0) > 0 }
}

/// Height, weight and the rest, for calorie estimates. Stored metric;
/// shown in the unit the lifter uses.
public struct BodyProfile: Codable, Equatable, Sendable {
    public var heightCm: Double?
    public var weightKg: Double?
    public var birthYear: Int?
    /// "male" / "female" / nil; only used by the calorie estimate.
    public var sex: String?

    public init(heightCm: Double? = nil, weightKg: Double? = nil, birthYear: Int? = nil, sex: String? = nil) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.birthYear = birthYear
        self.sex = sex
    }

    public var isEmpty: Bool { heightCm == nil && weightKg == nil && birthYear == nil && sex == nil }
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
    public var profile: BodyProfile
    /// Photos attached to exercises (built-in ones included), by exercise id.
    public var exerciseImages: [String: String]
    /// Remembered from the finish sheet: post finished workouts to the
    /// Inner Circle feed.
    public var shareWithInnerCircle: Bool

    public init(unit: WeightUnit = .lb, restTimerSeconds: Int = 90, autoRestTimer: Bool = true, customExercises: [Exercise] = [],
                routines: [Routine] = [], prsByExercise: [String: PersonalRecord] = [:], activeSession: WorkoutSession? = nil,
                profile: BodyProfile = BodyProfile(), exerciseImages: [String: String] = [:], shareWithInnerCircle: Bool = false) {
        self.unit = unit
        self.restTimerSeconds = restTimerSeconds
        self.autoRestTimer = autoRestTimer
        self.customExercises = customExercises
        self.routines = routines
        self.prsByExercise = prsByExercise
        self.activeSession = activeSession
        self.profile = profile
        self.exerciseImages = exerciseImages
        self.shareWithInnerCircle = shareWithInnerCircle
    }

    private enum CodingKeys: String, CodingKey {
        case unit, restTimerSeconds, autoRestTimer, customExercises, routines, prsByExercise, activeSession
        case profile, exerciseImages, shareWithInnerCircle
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
        profile = try c.decodeIfPresent(BodyProfile.self, forKey: .profile) ?? BodyProfile()
        exerciseImages = try c.decodeIfPresent([String: String].self, forKey: .exerciseImages) ?? [:]
        shareWithInnerCircle = try c.decodeIfPresent(Bool.self, forKey: .shareWithInnerCircle) ?? false
    }

    /// The photo for an exercise: the attached one, else the custom
    /// exercise's own.
    public func imageURL(for exerciseId: String) -> URL? {
        if let url = exerciseImages[exerciseId] { return URL(string: url) }
        return exercise(id: exerciseId)?.imageUrl.flatMap(URL.init(string:))
    }

    /// Distance unit follows the lifting unit.
    public var distanceUnit: String { unit == .kg ? "km" : "mi" }

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

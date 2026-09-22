import Foundation

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
    /// Which named Inner Circle list the finished workout is posted to; nil
    /// means anyone on any of the person's lists.
    public var shareListId: String?

    public init(unit: WeightUnit = .lb, restTimerSeconds: Int = 90, autoRestTimer: Bool = true, customExercises: [Exercise] = [],
                routines: [Routine] = [], prsByExercise: [String: PersonalRecord] = [:], activeSession: WorkoutSession? = nil,
                profile: BodyProfile = BodyProfile(), exerciseImages: [String: String] = [:], shareWithInnerCircle: Bool = false, shareListId: String? = nil) {
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
        self.shareListId = shareListId
    }

    private enum CodingKeys: String, CodingKey {
        case unit, restTimerSeconds, autoRestTimer, customExercises, routines, prsByExercise, activeSession
        case profile, exerciseImages, shareWithInnerCircle, shareListId
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
        shareListId = try c.decodeIfPresent(String.self, forKey: .shareListId)
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

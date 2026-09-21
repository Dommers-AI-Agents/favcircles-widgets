import Foundation

/// Pure rules for building, editing and finishing a workout session. The
/// SwiftUI layer calls these inside `settings.update { … }` so the
/// in-progress workout is always the persisted one.
public enum WorkoutSessionLogic {
    /// Distinct exercises in the order they first appear in the session —
    /// the block order the active-session screen renders.
    public static func orderedExerciseIds(in session: WorkoutSession) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for set in session.sets where seen.insert(set.exerciseId).inserted {
            order.append(set.exerciseId)
        }
        return order
    }

    /// The session's sets with whole exercise blocks moved (List `onMove`
    /// semantics on `orderedExerciseIds`). Rows keep their relative order
    /// inside each block; nothing is dropped.
    public static func movingExercises(in session: WorkoutSession, fromOffsets source: IndexSet, toOffset destination: Int) -> [SetEntry] {
        let order = orderedExerciseIds(in: session)
        // SwiftUI's move(fromOffsets:toOffset:) semantics, without SwiftUI:
        // pull the picked ids out, then insert them at `destination` as it
        // was numbered before the removal.
        let picked = source.sorted().compactMap { $0 < order.count ? order[$0] : nil }
        var remaining = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = max(0, min(remaining.count, destination - removedBefore))
        remaining.insert(contentsOf: picked, at: insertAt)
        return remaining.flatMap { id in session.sets.filter { $0.exerciseId == id } }
    }

    /// A session prefilled from a routine: every item becomes `targetSets`
    /// empty rows (0 × 0). The UI shows the routine's target reps as the
    /// placeholder and fills them in when a row is ticked untouched.
    public static func session(from routine: Routine, startedAt: Date = Date()) -> WorkoutSession {
        var sets: [SetEntry] = []
        for item in routine.items {
            for _ in 0..<max(1, item.targetSets) {
                sets.append(SetEntry(exerciseId: item.exerciseId, reps: 0, weight: 0))
            }
        }
        return WorkoutSession(routineId: routine.id, name: routine.name, startedAt: startedAt, sets: sets)
    }

    /// A blank set row. It stays 0 × 0 on purpose: the values you would
    /// repeat arrive as the row's placeholder (see `targets(for:)`) and are
    /// written in when you tick it, so an untouched extra row is still
    /// untouched and is dropped at the end.
    public static func nextSet(for exerciseId: String) -> SetEntry {
        SetEntry(exerciseId: exerciseId, reps: 0, weight: 0)
    }

    /// What a row should offer before anyone types in it.
    public struct SetTarget: Equatable, Sendable {
        public let reps: Int?
        public let weight: Double?

        public init(reps: Int?, weight: Double?) {
            self.reps = reps
            self.weight = weight
        }

        public var isEmpty: Bool { reps == nil && weight == nil }
    }

    /// A target for each row of one exercise, in order.
    ///
    /// The values roll forward: every row offers what the last completed
    /// working set of that exercise actually was, so changing the weight on
    /// set two carries into sets three and four without retyping. Before
    /// anything is ticked the routine's remembered values stand in. Warm-up
    /// sets never set the working target.
    public static func targets(for sets: [SetEntry], routineReps: Int? = nil, routineWeight: Double? = nil) -> [SetTarget] {
        var reps = routineReps
        var weight = routineWeight.flatMap { $0 > 0 ? $0 : nil }
        var out: [SetTarget] = []
        for set in sets {
            out.append(SetTarget(reps: reps, weight: weight))
            guard set.completedAt != nil, !set.isWarmup else { continue }
            if set.reps > 0 { reps = set.reps }
            if set.weight > 0 { weight = set.weight }
        }
        return out
    }

    /// The routine item behind an exercise in this session, if any.
    public static func routineItem(for exerciseId: String, in session: WorkoutSession, routines: [Routine]) -> RoutineItem? {
        guard let routineId = session.routineId,
              let routine = routines.first(where: { $0.id == routineId }) else { return nil }
        return routine.items.first { $0.exerciseId == exerciseId }
    }

    /// A row holds user data when it was ticked or has any number typed in
    /// (weight or reps — bodyweight sets have no weight). Untouched
    /// placeholders (0 × 0, never completed) hold none.
    public static func holdsUserData(_ set: SetEntry) -> Bool {
        set.completedAt != nil || set.weight > 0 || set.reps > 0
    }

    /// The routine's target reps for an exercise in this session, if it
    /// came from a routine.
    public static func targetReps(for exerciseId: String, in session: WorkoutSession, routines: [Routine]) -> Int? {
        guard let routineId = session.routineId,
              let routine = routines.first(where: { $0.id == routineId }) else { return nil }
        return routine.items.first { $0.exerciseId == exerciseId }?.targetReps
    }

    /// What the routine would become after this workout, or nil when the
    /// session came from no routine, or matches the one it came from.
    ///
    /// Each exercise keeps the values of its FIRST completed working set:
    /// straight sets record themselves exactly, and someone who ramps up
    /// gets their opening set back next time rather than their heaviest.
    /// Exercises added during the workout are appended; exercises that were
    /// skipped are left alone, because not doing something once is not a
    /// decision to remove it.
    public static func routineUpdate(for session: WorkoutSession, routines: [Routine],
                                     name: @escaping (String) -> String = { $0 },
                                     unit: WeightUnit = .lb) -> RoutineUpdate? {
        guard let routineId = session.routineId else { return nil }
        guard let existing = routines.first(where: { $0.id == routineId }) else { return nil }

        var items = existing.items
        var changes: [String] = []
        for exerciseId in orderedExerciseIds(in: session) {
            let performed = session.sets.filter { $0.exerciseId == exerciseId && $0.completedAt != nil && !$0.isWarmup }
            guard let first = performed.first else { continue }
            let sets = performed.count
            let reps = first.reps
            let weight = first.weight > 0 ? first.weight : nil
            let line = describe(sets: sets, reps: reps, weight: weight, unit: unit)
            if let index = items.firstIndex(where: { $0.exerciseId == exerciseId }) {
                let was = items[index]
                let wasLine = describe(sets: was.targetSets, reps: was.targetReps, weight: was.targetWeight, unit: unit)
                guard wasLine != line else { continue }
                items[index].targetSets = sets
                items[index].targetReps = reps
                items[index].targetWeight = weight
                changes.append("\(name(exerciseId)): \(wasLine) → \(line)")
            } else {
                items.append(RoutineItem(exerciseId: exerciseId, targetSets: sets, targetReps: reps, targetWeight: weight))
                changes.append("\(name(exerciseId)): added, \(line)")
            }
        }
        guard !changes.isEmpty else { return nil }
        return RoutineUpdate(routine: Routine(id: existing.id, name: existing.name, items: items),
                             isNew: false, changes: changes)
    }

    /// "3 × 10 at 135 lb", or "3 × 10" when there is no weight.
    static func describe(sets: Int, reps: Int, weight: Double?, unit: WeightUnit) -> String {
        let base = "\(sets) × \(reps)"
        guard let weight, weight > 0 else { return base }
        return "\(base) at \(WorkoutNumber.trim(weight)) \(unit.label)"
    }

    /// The routines list with an accepted update written in; a routine that
    /// only existed in the starter list is added as the person's own.
    public static func applying(_ update: RoutineUpdate, to routines: [Routine]) -> [Routine] {
        var out = routines
        if let index = out.firstIndex(where: { $0.id == update.routine.id }) {
            out[index] = update.routine
        } else {
            out.append(update.routine)
        }
        return out
    }

    public static func completedSetCount(_ session: WorkoutSession) -> Int {
        session.sets.filter { $0.completedAt != nil }.count
    }

    /// Anything worth saving: a set with data, or a cardio entry with data.
    public static func hasUserData(_ session: WorkoutSession) -> Bool {
        session.sets.contains(where: holdsUserData) || session.cardio.contains(where: \.holdsUserData)
    }

    public static func duration(of session: WorkoutSession, now: Date = Date()) -> TimeInterval {
        max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt))
    }

    /// The outcome of finishing a workout: the session as it will be
    /// stored, and the records it set.
    public struct FinishResult: Equatable, Sendable {
        public let session: WorkoutSession
        public let newRecords: [String: PersonalRecord]
    }

    /// Stamps `endedAt`, drops only the placeholder rows that hold no user
    /// data (typed-but-unticked sets are kept), and detects PRs from the
    /// completed working sets.
    public static func finish(_ session: WorkoutSession, existingRecords: [String: PersonalRecord], at endedAt: Date = Date()) -> FinishResult {
        var finished = session
        finished.endedAt = endedAt
        finished.sets = session.sets.filter(holdsUserData)
        finished.cardio = session.cardio.filter(\.holdsUserData).map { entry in
            var e = entry
            if e.completedAt == nil { e.completedAt = endedAt }
            return e
        }
        var completedOnly = finished
        completedOnly.sets = finished.sets.filter { $0.completedAt != nil }
        let records = PRDetector.newRecords(in: completedOnly, existing: existingRecords)
        return FinishResult(session: finished, newRecords: records)
    }

    /// Merges freshly set records into the running table.
    public static func applying(_ records: [String: PersonalRecord], to existing: [String: PersonalRecord]) -> [String: PersonalRecord] {
        existing.merging(records) { _, new in new }
    }

    /// Records set during `month`, for the card's "3 PRs this month".
    public static func recordCount(in records: [String: PersonalRecord], month: MonthKey, calendar: Calendar) -> Int {
        records.values.filter { MonthKey($0.date, calendar: calendar) == month }.count
    }

    /// Newest finished session across any number of month logs.
    public static func lastSession(in months: [WorkoutMonth]) -> WorkoutSession? {
        months.flatMap(\.sessions).filter { !$0.isActive }.max { $0.startedAt < $1.startedAt }
    }
}

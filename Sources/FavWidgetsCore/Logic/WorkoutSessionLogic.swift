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

    /// A blank set row for an exercise, copying weight/reps from the last
    /// row of the same exercise so "Add set" repeats the previous set.
    public static func nextSet(for exerciseId: String, in session: WorkoutSession) -> SetEntry {
        if let last = session.sets.last(where: { $0.exerciseId == exerciseId }) {
            return SetEntry(exerciseId: exerciseId, reps: last.reps, weight: last.weight)
        }
        return SetEntry(exerciseId: exerciseId, reps: 0, weight: 0)
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

    public static func completedSetCount(_ session: WorkoutSession) -> Int {
        session.sets.filter { $0.completedAt != nil }.count
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

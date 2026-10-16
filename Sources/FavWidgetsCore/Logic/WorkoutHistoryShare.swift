import Foundation

/// The workout history someone's Inner Circle may browse (Wes, 2026-10-16:
/// "Allow my inner circle to view my workout history"). Custom exercise
/// names live only on the phone, so the phone sends these summaries.
public enum WorkoutHistoryShare {
    /// How far back the shared history reaches.
    public static let months = 12
    /// The most workouts sent (the server keeps the same number).
    public static let maxWorkouts = 200

    /// Finished workouts, newest first, as share summaries. A workout still
    /// holding a current PR is marked with it.
    public static func summaries(_ sessions: [WorkoutSession], settings: WorkoutSettings) -> [WorkoutShareSummary] {
        let finished = sessions.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }.prefix(maxWorkouts)
        return finished.compactMap { session in
            let records = settings.prsByExercise.filter { $0.value.sessionId == session.id }
            let summary = WorkoutShareSummary.make(session: session, newRecords: records, unit: settings.unit,
                                                   weightKg: settings.profile.weightKg,
                                                   exerciseName: { settings.exercise(id: $0)?.name ?? "Exercise" },
                                                   exerciseInfo: { settings.exercise(id: $0) })
            // Nothing logged: the server would refuse it anyway
            return summary.exercises.isEmpty && summary.cardio.isEmpty ? nil : summary
        }
    }
}

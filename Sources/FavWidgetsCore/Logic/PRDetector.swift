import Foundation

public enum PRDetector {
    /// Epley estimate; a single rep is the lift itself.
    public static func estimatedOneRM(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// PRs set by a session's working sets, compared with the running
    /// records. Returns only the exercises that improved.
    public static func newRecords(in session: WorkoutSession, existing: [String: PersonalRecord]) -> [String: PersonalRecord] {
        var improved: [String: PersonalRecord] = [:]
        for set in session.sets where !set.isWarmup && set.reps > 0 && set.weight > 0 {
            let e1rm = estimatedOneRM(weight: set.weight, reps: set.reps)
            let currentBest = improved[set.exerciseId]?.estimatedOneRM ?? existing[set.exerciseId]?.estimatedOneRM ?? 0
            if e1rm > currentBest {
                improved[set.exerciseId] = PersonalRecord(
                    weight: set.weight, reps: set.reps, estimatedOneRM: e1rm,
                    date: set.completedAt ?? session.startedAt, sessionId: session.id
                )
            }
        }
        return improved
    }
}

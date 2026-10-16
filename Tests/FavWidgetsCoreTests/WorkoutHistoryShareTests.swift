import Foundation
import Testing
@testable import FavWidgetsCore

struct WorkoutHistoryShareTests {
    private func session(_ name: String, daysAgo: Double, finished: Bool = true, logged: Bool = true) -> WorkoutSession {
        let start = Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86_400)
        let sets = logged ? [SetEntry(exerciseId: "bench_press", reps: 5, weight: 185, completedAt: start.addingTimeInterval(600))] : []
        return WorkoutSession(name: name, startedAt: start, endedAt: finished ? start.addingTimeInterval(3_000) : nil, sets: sets)
    }

    @Test func finishedLoggedWorkoutsNewestFirst() {
        let sessions = [session("Old", daysAgo: 9), session("New", daysAgo: 1), session("Live", daysAgo: 0, finished: false),
                        session("Empty", daysAgo: 3, logged: false)]
        let out = WorkoutHistoryShare.summaries(sessions, settings: WorkoutSettings())
        #expect(out.map(\.name) == ["New", "Old"])
        #expect(out[0].exercises.first?.bestSet == "185 lb × 5")
    }

    @Test func aCurrentRecordIsMarkedOnItsWorkout() {
        let s = session("Push", daysAgo: 2)
        var settings = WorkoutSettings()
        settings.prsByExercise["bench_press"] = PersonalRecord(weight: 185, reps: 5, estimatedOneRM: 208, date: s.startedAt, sessionId: s.id)
        let out = WorkoutHistoryShare.summaries([s, session("Other", daysAgo: 5)], settings: settings)
        #expect(out[0].prCount == 1 && out[0].exercises[0].isPR)
        #expect(out[1].prCount == 0)
    }
}

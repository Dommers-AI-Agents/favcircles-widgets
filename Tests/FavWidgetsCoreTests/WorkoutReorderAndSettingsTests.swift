import Testing
import Foundation
@testable import FavWidgetsCore

struct WorkoutReorderAndSettingsTests {
    private func session() -> WorkoutSession {
        var s = WorkoutSession(name: "Push")
        s.sets = [
            SetEntry(exerciseId: "bench_press", reps: 8, weight: 100),
            SetEntry(exerciseId: "bench_press", reps: 8, weight: 105),
            SetEntry(exerciseId: "overhead_press", reps: 10, weight: 60),
            SetEntry(exerciseId: "tricep_pushdown", reps: 12, weight: 40),
            SetEntry(exerciseId: "tricep_pushdown", reps: 12, weight: 45),
            SetEntry(exerciseId: "tricep_pushdown", reps: 12, weight: 50)
        ]
        return s
    }

    @Test func movingAnExerciseMovesItsWholeBlockAndKeepsRowOrder() {
        let s = session()
        // List onMove semantics: move the last exercise to the front
        let moved = WorkoutSessionLogic.movingExercises(in: s, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(moved.map(\.exerciseId) == ["tricep_pushdown", "tricep_pushdown", "tricep_pushdown", "bench_press", "bench_press", "overhead_press"])
        #expect(moved.filter { $0.exerciseId == "tricep_pushdown" }.map(\.weight) == [40, 45, 50])
        #expect(moved.count == s.sets.count)
        #expect(Set(moved.map(\.id)) == Set(s.sets.map(\.id)))
    }

    @Test func movingToTheEndAndNoOpMoves() {
        let s = session()
        let toEnd = WorkoutSessionLogic.movingExercises(in: s, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(WorkoutSessionLogic.orderedExerciseIds(in: WorkoutSession(name: "x", sets: toEnd)) == ["overhead_press", "tricep_pushdown", "bench_press"])
        let same = WorkoutSessionLogic.movingExercises(in: s, fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(same == s.sets)
    }

    @Test func settingsDecodeWithoutTheNewFieldDefaultToAutoRest() throws {
        let legacy = Data(#"{"unit":"kg","restTimerSeconds":120,"customExercises":[],"routines":[],"prsByExercise":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(WorkoutSettings.self, from: legacy)
        #expect(decoded.autoRestTimer == true)
        #expect(decoded.unit == .kg && decoded.restTimerSeconds == 120)

        let off = Data(#"{"autoRestTimer":false}"#.utf8)
        let sparse = try JSONDecoder().decode(WorkoutSettings.self, from: off)
        #expect(sparse.autoRestTimer == false)
        #expect(sparse.unit == .lb && sparse.restTimerSeconds == 90 && sparse.activeSession == nil)
    }

    @Test func settingsRoundTripKeepsAutoRest() throws {
        var settings = WorkoutSettings()
        settings.autoRestTimer = false
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(WorkoutSettings.self, from: data)
        #expect(back == settings)
    }
}

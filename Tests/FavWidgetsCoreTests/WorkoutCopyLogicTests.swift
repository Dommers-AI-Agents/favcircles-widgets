import Testing
import Foundation
@testable import FavWidgetsCore

/// Copying someone's shared workout as your own routine.
struct WorkoutCopyLogicTests {

    private func summary(routine: [WorkoutShareSummary.RoutineLine]?, exercises: [WorkoutShareSummary.ExerciseLine] = []) -> WorkoutShareSummary {
        WorkoutShareSummary(name: "Shoulders", startedAt: Date(), durationSeconds: 2400, completedSets: 9,
                            exercises: exercises, cardio: [], prCount: 0, unit: "lb", routine: routine)
    }

    @Test func builtInsKeepTheirIdCustomsMatchByNameOrAreCreated() {
        let mine = Exercise(id: "my-shrug", name: "Shrug", muscleGroup: "Back")
        let settings = WorkoutSettings(customExercises: [mine])
        let shared = summary(routine: [
            .init(exerciseId: "overhead_press", name: "Overhead Press", muscleGroup: "Shoulders", sets: 3, reps: 10, weight: 50),
            .init(exerciseId: "their-uuid-1", name: "shrug ", muscleGroup: "Back", sets: 4, reps: 20, weight: 75),
            .init(exerciseId: "their-uuid-2", name: "Upright rows", muscleGroup: "Shoulders", sets: 2, reps: 12, weight: 70)
        ])
        let copy = WorkoutCopyLogic.copy(shared, named: "Shoulders", into: settings)
        #expect(copy.routine.items.map(\.exerciseId).prefix(2) == ["overhead_press", "my-shrug"])
        #expect(copy.newExercises.map(\.name) == ["Upright rows"])
        #expect(copy.routine.items[2].exerciseId == copy.newExercises[0].id)
        #expect(copy.routine.items.map(\.targetSets) == [3, 4, 2])
        #expect(copy.routine.items.map(\.targetReps) == [10, 20, 12])
        // Someone else's weights never become yours
        #expect(copy.routine.items.allSatisfy { $0.targetWeight == nil })
    }

    @Test func olderPostsRebuildFromTheExerciseLines() {
        let shared = summary(routine: nil, exercises: [
            .init(name: "Bench Press", sets: 4, bestSet: "175 lb × 8", isPR: false),
            .init(name: "Push-Up", sets: 2, bestSet: "20 reps", isPR: false)
        ])
        let copy = WorkoutCopyLogic.copy(shared, named: "Push", into: WorkoutSettings())
        #expect(copy.routine.items.map(\.exerciseId) == ["bench_press", "push_up"])
        #expect(copy.routine.items.map(\.targetReps) == [8, 20])
        #expect(copy.newExercises.isEmpty)
    }

    @Test func namesDontClashWithYourRoutines() {
        let existing = [Routine(name: "Shoulders"), Routine(name: "Shoulders · Brittany")]
        #expect(WorkoutCopyLogic.routineName("Legs", author: "Brittany Sgroi", existing: existing) == "Legs")
        #expect(WorkoutCopyLogic.routineName("Shoulders", author: "Brittany Sgroi", existing: []) == "Shoulders")
        #expect(WorkoutCopyLogic.routineName("shoulders", author: "Brittany Sgroi", existing: existing) == "shoulders · Brittany 2")
    }

    @Test func aSecondVisitFindsTheCopyInsteadOfDuplicating() {
        let shared = summary(routine: [.init(exerciseId: "squat", name: "Squat", muscleGroup: "Legs", sets: 3, reps: 5, weight: nil)])
        var settings = WorkoutSettings()
        #expect(WorkoutCopyLogic.existingCopy(of: shared, in: settings) == nil)
        let copy = WorkoutCopyLogic.copy(shared, named: "Legs", into: settings)
        settings.routines.append(copy.routine)
        #expect(WorkoutCopyLogic.existingCopy(of: shared, in: settings)?.id == copy.routine.id)
    }

    @Test func theSharedSummaryCarriesACopyableRoutine() {
        var first = SetEntry(exerciseId: "overhead_press", reps: 10, weight: 50, completedAt: Date())
        var warm = SetEntry(exerciseId: "overhead_press", reps: 12, weight: 20, isWarmup: true, completedAt: Date())
        warm.completedAt = Date()
        first.completedAt = Date()
        let second = SetEntry(exerciseId: "overhead_press", reps: 8, weight: 55, completedAt: Date())
        let untouched = SetEntry(exerciseId: "squat", reps: 25, weight: 180, isPrefilled: true)
        let session = WorkoutSession(name: "Shoulders", endedAt: Date(), sets: [warm, first, second, untouched])
        let s = WorkoutShareSummary.make(session: session, newRecords: [:], unit: .lb, weightKg: nil,
                                         exerciseName: { $0 }, exerciseInfo: { id in ExerciseCatalog.builtIn.first { $0.id == id } })
        #expect(s.routine == [.init(exerciseId: "overhead_press", name: "Overhead Press", muscleGroup: "Shoulders", sets: 2, reps: 10, weight: 50)])
    }
}

import Testing
import Foundation
@testable import FavWidgetsCore

/// The workout on the lock screen (2026-10-30): the next set and its
/// numbers, ticking it from there, and keeping that tick when the open
/// workout screen saves over it.
struct WorkoutLivePlanTests {
    private func settings(_ sets: [SetEntry], unit: WeightUnit = .lb) -> WorkoutSettings {
        WorkoutSettings(unit: unit, activeSession: WorkoutSession(name: "Push", sets: sets))
    }

    @Test func theNextSetIsTheFirstUntickedInExerciseOrderWithItsNumbers() {
        let s = settings([
            SetEntry(exerciseId: "bench_press", reps: 8, weight: 135, completedAt: Date()),
            SetEntry(exerciseId: "bench_press", reps: 0, weight: 0),
            SetEntry(exerciseId: "bench_press", reps: 0, weight: 0),
            SetEntry(exerciseId: "squat", reps: 5, weight: 225)
        ])
        let state = try! #require(WorkoutLivePlan.state(s))
        #expect(state.doneSets == 1 && state.totalSets == 4)
        // An empty row offers what the last done set was
        #expect(state.next?.setNumber == 2 && state.next?.setsInExercise == 3)
        #expect(state.nextNumbers == "135 lb × 8")
        #expect(state.nextSetLabel == "Set 2 of 3")
        #expect(WorkoutLivePlan.state(WorkoutSettings()) == nil)
    }

    @Test func everySetDoneLeavesNoNextSet() {
        let s = settings([SetEntry(exerciseId: "squat", reps: 5, weight: 225, completedAt: Date())])
        let state = try! #require(WorkoutLivePlan.state(s))
        #expect(state.next == nil && state.nextNumbers == nil)
    }

    @Test func doneFromTheLockScreenFillsAndCarriesLikeTheRowDoes() {
        let first = SetEntry(exerciseId: "bench_press", reps: 0, weight: 0)
        var s = settings([
            SetEntry(exerciseId: "bench_press", reps: 8, weight: 135, completedAt: Date()),
            first,
            SetEntry(exerciseId: "bench_press", reps: 8, weight: 135, isPrefilled: true)
        ])
        #expect(WorkoutLivePlan.completeSet(first.id, in: &s))
        let done = try! #require(s.activeSession?.sets[1])
        #expect(done.completedAt != nil && done.reps == 8 && done.weight == 135 && done.isPrefilled == nil)
        // Already done: nothing to do
        #expect(!WorkoutLivePlan.completeSet(first.id, in: &s))
    }

    @Test func aSetTickedElsewhereSurvivesTheOpenScreensSave() {
        let a = SetEntry(exerciseId: "squat", reps: 5, weight: 225)
        let b = SetEntry(exerciseId: "squat", reps: 5, weight: 225)
        let session = WorkoutSession(name: "Legs", sets: [a, b])
        var local = WorkoutSettings(activeSession: session)
        var remote = local
        remote.activeSession?.sets[0].completedAt = Date()          // ticked on the lock screen
        local.activeSession?.sets[1].reps = 6                       // typed on the open screen
        let merged = WorkoutSettings.merge(local: local, remote: remote)
        #expect(merged.activeSession?.sets[0].completedAt != nil)
        #expect(merged.activeSession?.sets[1].reps == 6)
        // A different workout on the other copy: the screen's stands
        var other = remote; other.activeSession = WorkoutSession(name: "Other")
        #expect(WorkoutSettings.merge(local: local, remote: other) == local)
    }

    @Test func theQuickLogSavesTheTickAndAnnouncesIt() async throws {
        let store = InMemoryWidgetDataStore()
        let set = SetEntry(exerciseId: "squat", reps: 5, weight: 225)
        let seed = settings([set])
        _ = try await store.save(id: WorkoutQuickLog.documentId,
                                 document: WidgetDocument(version: 0, payload: try WidgetDocumentCodec.encode(seed),
                                                          schemaVersion: WorkoutQuickLog.schemaVersion))
        let saved = try await WorkoutQuickLog.completeSet(set.id, store: store)
        #expect(saved.activeSession?.sets.first?.completedAt != nil)
        let reloaded = await WorkoutQuickLog.load(store: store)
        #expect(reloaded?.activeSession?.sets.first?.completedAt != nil)
    }
}

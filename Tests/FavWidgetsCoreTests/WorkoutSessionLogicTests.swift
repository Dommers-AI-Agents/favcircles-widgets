import Testing
import Foundation
@testable import FavWidgetsCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

struct WorkoutSessionLogicTests {
    @Test func routineBecomesPlaceholderRowsInOrder() {
        let routine = ExerciseCatalog.starterRoutines[0]   // Push: 4+3+3+3 sets
        let session = WorkoutSessionLogic.session(from: routine)
        #expect(session.sets.count == 13)
        #expect(session.routineId == routine.id && session.name == "Push")
        #expect(WorkoutSessionLogic.orderedExerciseIds(in: session) == ["bench_press", "overhead_press", "incline_db_press", "tricep_pushdown"])
        #expect(session.sets.first?.reps == 0 && session.sets.first?.weight == 0 && session.sets.first?.completedAt == nil)
        #expect(WorkoutSessionLogic.targetReps(for: "bench_press", in: session, routines: ExerciseCatalog.starterRoutines) == 8)
        #expect(WorkoutSessionLogic.targetReps(for: "squat", in: session, routines: ExerciseCatalog.starterRoutines) == nil)
        #expect(!session.sets.contains(where: WorkoutSessionLogic.holdsUserData))
        #expect(WorkoutSessionLogic.completedSetCount(session) == 0)
    }

    @Test func anAddedSetStartsEmptyAndIsOfferedTheLastValues() {
        // The row itself is blank — an untouched extra row must still be
        // dropped at the end — and what to repeat arrives as its target.
        let next = WorkoutSessionLogic.nextSet(for: "squat")
        #expect(next.reps == 0 && next.weight == 0 && next.completedAt == nil)
        #expect(!WorkoutSessionLogic.holdsUserData(next))

        let done = SetEntry(exerciseId: "squat", reps: 5, weight: 120, completedAt: Date())
        let targets = WorkoutSessionLogic.targets(for: [done, next])
        #expect(targets[1] == WorkoutSessionLogic.SetTarget(reps: 5, weight: 120))
    }

    @Test func targetsRollForwardFromTheLastCompletedWorkingSet() {
        let blank = { SetEntry(exerciseId: "bench", reps: 0, weight: 0) }
        let sets = [
            SetEntry(exerciseId: "bench", reps: 12, weight: 45, isWarmup: true, completedAt: Date()),  // warm-up
            SetEntry(exerciseId: "bench", reps: 10, weight: 135, completedAt: Date()),
            SetEntry(exerciseId: "bench", reps: 8, weight: 145, completedAt: Date()),
            blank(), blank()
        ]
        let targets = WorkoutSessionLogic.targets(for: sets, routineReps: 10, routineWeight: 135)
        // Row 1 gets the routine; the warm-up does not become the target.
        #expect(targets[0] == WorkoutSessionLogic.SetTarget(reps: 10, weight: 135))
        #expect(targets[1] == WorkoutSessionLogic.SetTarget(reps: 10, weight: 135))
        // Once 145 × 8 is ticked, the rest of the block offers that.
        #expect(targets[3] == WorkoutSessionLogic.SetTarget(reps: 8, weight: 145))
        #expect(targets[4] == WorkoutSessionLogic.SetTarget(reps: 8, weight: 145))
        // With no routine and nothing done, there is nothing to offer.
        #expect(WorkoutSessionLogic.targets(for: [blank()])[0].isEmpty)
    }

    @Test func routineUpdateProposesWhatWasActuallyDone() {
        let routine = Routine(id: UUID(), name: "Push", items: [
            RoutineItem(exerciseId: "bench", targetSets: 3, targetReps: 10, targetWeight: 135),
            RoutineItem(exerciseId: "fly", targetSets: 3, targetReps: 12)
        ])
        var session = WorkoutSession(routineId: routine.id, name: "Push")
        // Bench: a warm-up, then four working sets that ramp. The routine
        // should record where the work STARTED (145 × 8), not the heaviest.
        session.sets = [
            SetEntry(exerciseId: "bench", reps: 12, weight: 45, isWarmup: true, completedAt: Date()),
            SetEntry(exerciseId: "bench", reps: 8, weight: 145, completedAt: Date()),
            SetEntry(exerciseId: "bench", reps: 8, weight: 155, completedAt: Date()),
            SetEntry(exerciseId: "bench", reps: 6, weight: 165, completedAt: Date()),
            SetEntry(exerciseId: "bench", reps: 5, weight: 175, completedAt: Date()),
            // Fly: skipped entirely, so it must be left alone, not removed.
            SetEntry(exerciseId: "fly", reps: 0, weight: 0),
            // Added on the day.
            SetEntry(exerciseId: "dip", reps: 10, weight: 0, completedAt: Date())
        ]
        let update = WorkoutSessionLogic.routineUpdate(for: session, routines: [routine])
        #expect(update != nil)
        let items = update!.routine.items
        #expect(update!.routine.id == routine.id && update!.routine.name == "Push")
        #expect(items.first { $0.exerciseId == "bench" } == RoutineItem(id: items[0].id, exerciseId: "bench", targetSets: 4, targetReps: 8, targetWeight: 145))
        #expect(items.first { $0.exerciseId == "fly" }?.targetReps == 12)       // untouched
        #expect(items.first { $0.exerciseId == "dip" }?.targetSets == 1)        // appended
        #expect(update!.changes.contains { $0.contains("3 × 10 at 135 lb → 4 × 8 at 145 lb") })
        #expect(update!.changes.contains { $0.contains("added") })
    }

    @Test func nothingToAskWhenTheWorkoutMatchedOrHadNoRoutine() {
        let routine = Routine(id: UUID(), name: "Push", items: [
            RoutineItem(exerciseId: "bench", targetSets: 2, targetReps: 10, targetWeight: 135)
        ])
        var session = WorkoutSession(routineId: routine.id, name: "Push")
        session.sets = [
            SetEntry(exerciseId: "bench", reps: 10, weight: 135, completedAt: Date()),
            SetEntry(exerciseId: "bench", reps: 10, weight: 135, completedAt: Date())
        ]
        #expect(WorkoutSessionLogic.routineUpdate(for: session, routines: [routine]) == nil)
        // An ad-hoc workout has no routine to update.
        var adhoc = WorkoutSession(name: "Workout")
        adhoc.sets = [SetEntry(exerciseId: "bench", reps: 10, weight: 135, completedAt: Date())]
        #expect(WorkoutSessionLogic.routineUpdate(for: adhoc, routines: [routine]) == nil)
        // A routine the person doesn't own yet is added by `applying`.
        let starter = Routine(id: UUID(), name: "Pull", items: [])
        #expect(WorkoutSessionLogic.applying(RoutineUpdate(routine: starter, isNew: true, changes: []), to: [routine]).count == 2)
        #expect(WorkoutSessionLogic.applying(RoutineUpdate(routine: routine, isNew: false, changes: []), to: [routine]).count == 1)
    }

    @Test func finishKeepsTypedRowsDropsUntouchedAndFindsPRs() {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 9))!
        let done = start.addingTimeInterval(600)
        let session = WorkoutSession(name: "Push", startedAt: start, sets: [
            SetEntry(exerciseId: "bench_press", reps: 5, weight: 100, completedAt: done),
            SetEntry(exerciseId: "bench_press", reps: 3, weight: 110),          // typed, not ticked: kept, not a PR
            SetEntry(exerciseId: "bench_press", reps: 0, weight: 0),            // untouched placeholder: dropped
            SetEntry(exerciseId: "push_up", reps: 20, weight: 0),                // bodyweight, typed reps only: kept
            SetEntry(exerciseId: "overhead_press", reps: 10, weight: 40, isWarmup: true, completedAt: done)
        ])
        let result = WorkoutSessionLogic.finish(session, existingRecords: [:], at: start.addingTimeInterval(1800))
        #expect(result.session.sets.count == 4)
        #expect(result.session.sets.contains { $0.exerciseId == "push_up" && $0.reps == 20 })
        #expect(result.session.endedAt == start.addingTimeInterval(1800))
        #expect(WorkoutSessionLogic.duration(of: result.session) == 1800)
        #expect(result.newRecords.keys.sorted() == ["bench_press"])
        #expect(result.newRecords["bench_press"]?.weight == 100)
        let table = WorkoutSessionLogic.applying(result.newRecords, to: ["squat": PersonalRecord(weight: 1, reps: 1, estimatedOneRM: 1, date: start, sessionId: UUID())])
        #expect(table.count == 2)
        #expect(WorkoutSessionLogic.recordCount(in: table, month: MonthKey(rawValue: "2026-09"), calendar: cal) == 2)
        #expect(WorkoutSessionLogic.recordCount(in: table, month: MonthKey(rawValue: "2026-08"), calendar: cal) == 0)
    }

    @Test func lastSessionSpansMonthsAndIgnoresActive() {
        let aug = WorkoutSession(name: "Legs", startedAt: cal.date(from: DateComponents(year: 2026, month: 8, day: 30))!, endedAt: Date())
        let sep = WorkoutSession(name: "Pull", startedAt: cal.date(from: DateComponents(year: 2026, month: 9, day: 2))!, endedAt: Date())
        let active = WorkoutSession(name: "Now", startedAt: Date())
        let last = WorkoutSessionLogic.lastSession(in: [WorkoutMonth(sessions: [sep, active]), WorkoutMonth(sessions: [aug])])
        #expect(last?.name == "Pull")
        #expect(WorkoutSessionLogic.lastSession(in: [WorkoutMonth()]) == nil)
    }
}

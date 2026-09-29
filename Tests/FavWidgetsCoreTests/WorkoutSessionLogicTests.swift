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
        // No history: rows carry the routine's target reps, marked prefilled
        #expect(session.sets.first?.reps == 8 && session.sets.first?.completedAt == nil && session.sets.first?.isPrefilled == true)
        #expect(WorkoutSessionLogic.targetReps(for: "bench_press", in: session, routines: ExerciseCatalog.starterRoutines) == 8)
        #expect(WorkoutSessionLogic.targetReps(for: "squat", in: session, routines: ExerciseCatalog.starterRoutines) == nil)
        #expect(!session.sets.contains(where: WorkoutSessionLogic.holdsUserData))
        #expect(WorkoutSessionLogic.completedSetCount(session) == 0)
    }

    @Test func anAddedSetCopiesTheRowAboveAndStaysDroppable() {
        let above = SetEntry(exerciseId: "squat", reps: 5, weight: 120, completedAt: Date())
        let session = WorkoutSession(name: "W", sets: [above])
        let copied = WorkoutSessionLogic.nextSet(for: "squat", in: session)
        #expect(copied.reps == 5 && copied.weight == 120 && copied.isPrefilled == true)
        #expect(!WorkoutSessionLogic.holdsUserData(copied))

        // A brand-new exercise with no history starts blank
        let next = WorkoutSessionLogic.nextSet(for: "squat", in: WorkoutSession(name: "W"))
        #expect(next.reps == 0 && next.weight == 0 && next.isPrefilled == nil)
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

    // MARK: - Prefill from last time (schema 5)

    private func done(_ id: String, _ w: Double, _ r: Int, warm: Bool = false) -> SetEntry {
        SetEntry(exerciseId: id, reps: r, weight: w, isWarmup: warm, completedAt: Date())
    }

    @Test func lastSetsComeFromTheNewestFinishedSessionThatDidIt() {
        let old = WorkoutSession(name: "A", startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
                                 sets: [done("ohp", 45, 10)])
        let newer = WorkoutSession(name: "B", startedAt: Date(timeIntervalSince1970: 300), endedAt: Date(timeIntervalSince1970: 400),
                                   sets: [done("ohp", 20, 12, warm: true), done("ohp", 50, 18), done("ohp", 55, 14),
                                          SetEntry(exerciseId: "ohp", reps: 14, weight: 55)])   // typed, never ticked
        let unrelated = WorkoutSession(name: "C", startedAt: Date(timeIntervalSince1970: 500), endedAt: Date(timeIntervalSince1970: 600),
                                       sets: [done("squat", 180, 25)])
        let active = WorkoutSession(name: "D", startedAt: Date(timeIntervalSince1970: 700), sets: [done("ohp", 99, 1)])
        let last = WorkoutSessionLogic.lastSets(for: "ohp", in: [old, unrelated, newer, active])
        #expect(last.map(\.weight) == [50, 55])
        #expect(WorkoutSessionLogic.lastSets(for: "never", in: [newer]).isEmpty)
    }

    @Test func prefillFollowsLastTimePerSetThenRepeatsTheLast() {
        let last = [done("ohp", 50, 18), done("ohp", 55, 14)]
        let rows = WorkoutSessionLogic.prefilledSets(for: "ohp", count: 3, last: last)
        #expect(rows.map(\.weight) == [50, 55, 55])
        #expect(rows.map(\.reps) == [18, 14, 14])
        #expect(rows.allSatisfy { $0.isPrefilled == true && $0.completedAt == nil })

        // No history: the routine's remembered numbers
        let item = RoutineItem(exerciseId: "ohp", targetSets: 2, targetReps: 10, targetWeight: 40)
        let fromRoutine = WorkoutSessionLogic.prefilledSets(for: "ohp", count: 2, last: [], routineItem: item)
        #expect(fromRoutine.map(\.weight) == [40, 40] && fromRoutine.map(\.reps) == [10, 10])
    }

    @Test func sessionFromRoutineUsesHistoryOverRoutineTargets() {
        let routine = Routine(name: "Shoulders", items: [RoutineItem(exerciseId: "ohp", targetSets: 2, targetReps: 10, targetWeight: 40)])
        let history = [WorkoutSession(name: "Shoulders", startedAt: Date(timeIntervalSince1970: 1), endedAt: Date(timeIntervalSince1970: 2),
                                      sets: [done("ohp", 50, 18), done("ohp", 55, 14)])]
        let session = WorkoutSessionLogic.session(from: routine, history: history)
        #expect(session.sets.map(\.weight) == [50, 55])
    }

    @Test func finishDropsUntickedPrefilledRowsButKeepsTypedOnes() {
        let prefilled = SetEntry(exerciseId: "ohp", reps: 14, weight: 55, isPrefilled: true)
        let typed = SetEntry(exerciseId: "ohp", reps: 12, weight: 50)
        var ticked = SetEntry(exerciseId: "ohp", reps: 18, weight: 50, isPrefilled: true)
        ticked.completedAt = Date()
        let session = WorkoutSession(name: "W", sets: [ticked, prefilled, typed])
        #expect(WorkoutSessionLogic.hasUserData(session))
        #expect(!WorkoutSessionLogic.hasUserData(WorkoutSession(name: "W", sets: [prefilled])))
        let result = WorkoutSessionLogic.finish(session, existingRecords: [:])
        #expect(result.session.sets.count == 2)
        #expect(result.session.sets.allSatisfy { $0.isPrefilled == nil })
        #expect(WorkoutSession(name: "W", sets: [prefilled]).exerciseCount == 0)
    }

    @Test func aChangedSetRollsIntoUntouchedRowsBelowOnly() {
        var first = SetEntry(exerciseId: "ohp", reps: 12, weight: 60)
        first.completedAt = Date()
        let untouched = SetEntry(exerciseId: "ohp", reps: 18, weight: 50, isPrefilled: true)
        let typed = SetEntry(exerciseId: "ohp", reps: 8, weight: 65)
        let otherExercise = SetEntry(exerciseId: "squat", reps: 25, weight: 180, isPrefilled: true)
        let out = WorkoutSessionLogic.rollingForward(from: first.id, in: [first, untouched, typed, otherExercise])
        #expect(out[1].weight == 60 && out[1].reps == 12 && out[1].isPrefilled == true)
        #expect(out[2].weight == 65 && out[2].reps == 8)
        #expect(out[3].weight == 180)
    }

    @Test func routineUpdateAddsNewExercisesKeepsSkippedAndRemembersThePrevious() {
        let routine = Routine(name: "Shoulders", items: [RoutineItem(exerciseId: "ohp", targetSets: 3, targetReps: 10),
                                                        RoutineItem(exerciseId: "lateral", targetSets: 3, targetReps: 12)])
        let session = WorkoutSession(routineId: routine.id, name: "Shoulders", endedAt: Date(),
                                     sets: [done("ohp", 50, 10), done("ohp", 50, 10), done("ohp", 50, 10), done("shrug", 75, 20)])
        let update = WorkoutSessionLogic.routineUpdate(for: session, routines: [routine])
        #expect(update?.routine.items.map(\.exerciseId) == ["ohp", "lateral", "shrug"])
        #expect(update?.previous == routine)
        let applied = WorkoutSessionLogic.applying(update!, to: [routine])
        #expect(applied.first?.items.count == 3)
    }
}

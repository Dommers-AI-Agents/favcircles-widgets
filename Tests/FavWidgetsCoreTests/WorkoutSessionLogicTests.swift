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

    @Test func nextSetRepeatsTheLastRow() {
        var session = WorkoutSession(name: "Ad hoc")
        #expect(WorkoutSessionLogic.nextSet(for: "squat", in: session).weight == 0)
        session.sets.append(SetEntry(exerciseId: "squat", reps: 5, weight: 120))
        let next = WorkoutSessionLogic.nextSet(for: "squat", in: session)
        #expect(next.reps == 5 && next.weight == 120 && next.completedAt == nil)
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

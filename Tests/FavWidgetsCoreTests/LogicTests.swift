import Testing
import Foundation
@testable import FavWidgetsCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

struct DayKeyTests {
    @Test func roundTripsAndArithmetic() {
        let day = DayKey(rawValue: "2026-09-13")
        #expect(day.year == 2026 && day.month == 9 && day.day == 13)
        #expect(day.monthKey == MonthKey(rawValue: "2026-09"))
        #expect(day.adding(days: 18, calendar: cal).rawValue == "2026-10-01")
        #expect(day.adding(days: -13, calendar: cal).rawValue == "2026-08-31")
        #expect(MonthKey(rawValue: "2026-01").previous.rawValue == "2025-12")
        #expect(MonthKey(rawValue: "2026-12").next.rawValue == "2027-01")
        #expect(MonthKey(rawValue: "2024-02").dayCount(calendar: cal) == 29)
    }

    @Test func encodesAsPlainStrings() throws {
        let data = try WidgetDocumentCodec.encoder.encode([DayKey(rawValue: "2026-09-13"): 1])
        #expect(String(decoding: data, as: UTF8.self) == #"{"2026-09-13":1}"#)
        let months = try WidgetDocumentCodec.encoder.encode([MonthKey(rawValue: "2026-09"): [1, 2]])
        #expect(String(decoding: months, as: UTF8.self) == #"{"2026-09":[1,2]}"#)
        let habit = Habit(name: "Walk")
        var log = HabitLog(habits: [habit])
        log.setDone(true, habitId: habit.id, on: DayKey(rawValue: "2026-09-02"), calendar: cal)
        let json = String(decoding: try WidgetDocumentCodec.encode(log), as: UTF8.self)
        #expect(json.contains(#""completions":{""#) && json.contains(#""2026-09":"01"#))
        let decoded = try WidgetDocumentCodec.decode(HabitLog.self, from: Data(json.utf8))
        #expect(decoded.isDone(habit.id, on: DayKey(rawValue: "2026-09-02")))
    }
}

struct ShardPlannerTests {
    @Test func hotSetIsSettingsPlusTwoMonths() {
        let d = FavWidgetDescriptor(id: "calories", title: "", subtitle: "", symbolName: "", accentHex: "#000000", category: .health, storage: .monthly)
        let now = cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        #expect(WidgetShardPlanner.hotIds(for: d, now: now, calendar: cal) == ["calories", "calories_2026-01", "calories_2025-12"])
        let single = FavWidgetDescriptor(id: "water", title: "", subtitle: "", symbolName: "", accentHex: "#000000", category: .health)
        #expect(WidgetShardPlanner.hotIds(for: single, now: now, calendar: cal) == ["water"])
        #expect(WidgetShardPlanner.hotIds(for: [single, d], now: now, calendar: cal).first == "prefs")
        #expect(WidgetShardPlanner.month(fromShardId: "calories_2026-01") == MonthKey(rawValue: "2026-01"))
        #expect(WidgetShardPlanner.month(fromShardId: "calories") == nil)
        #expect(WidgetShardPlanner.month(fromShardId: "bill_split") == nil)
    }

    @Test func idsMatchTheServerRule() {
        #expect(FavWidgetDescriptor.isValidId("calories"))
        #expect(FavWidgetDescriptor.isValidId("calories_2026-09"))
        #expect(FavWidgetDescriptor.isValidId("prefs"))
        #expect(!FavWidgetDescriptor.isValidId("Calories"))
        #expect(!FavWidgetDescriptor.isValidId("_prefs"))
        #expect(!FavWidgetDescriptor.isValidId("a"))
    }
}

struct StreakTests {
    @Test func currentAndBestStreaks() {
        let created = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let habit = Habit(name: "Read", createdAt: created)
        var log = HabitLog(habits: [habit])
        for d in [1, 2, 3, 5, 6, 7, 8] {
            log.setDone(true, habitId: habit.id, on: DayKey(rawValue: String(format: "2026-09-%02d", d)), calendar: cal)
        }
        let today = DayKey(rawValue: "2026-09-09")   // today not yet done
        #expect(StreakCalculator.current(log: log, habit: habit, today: today, calendar: cal) == 4)
        #expect(StreakCalculator.best(log: log, habit: habit, today: today, calendar: cal) == 4)
        log.setDone(true, habitId: habit.id, on: today, calendar: cal)
        #expect(StreakCalculator.current(log: log, habit: habit, today: today, calendar: cal) == 5)
        #expect(StreakCalculator.best(log: log, habit: habit, today: today, calendar: cal) == 5)
    }

    @Test func weekdayScheduleSkipsOffDays() {
        let created = cal.date(from: DateComponents(year: 2026, month: 9, day: 7))!  // a Monday
        let habit = Habit(name: "Gym", schedule: .weekdays([2, 4, 6]), createdAt: created)  // Mon/Wed/Fri
        var log = HabitLog(habits: [habit])
        log.setDone(true, habitId: habit.id, on: DayKey(rawValue: "2026-09-07"), calendar: cal)
        log.setDone(true, habitId: habit.id, on: DayKey(rawValue: "2026-09-09"), calendar: cal)
        // Thursday the 10th is not due: streak is still 2
        #expect(StreakCalculator.current(log: log, habit: habit, today: DayKey(rawValue: "2026-09-10"), calendar: cal) == 2)
        // Missed Friday the 11th → looking from Saturday, streak is 0
        #expect(StreakCalculator.current(log: log, habit: habit, today: DayKey(rawValue: "2026-09-12"), calendar: cal) == 0)
        #expect(log.doneCount(on: DayKey(rawValue: "2026-09-10"), calendar: cal).due == 0)
    }

    @Test func mergeIsBitwiseOr() {
        let habit = Habit(name: "Walk")
        var a = HabitLog(habits: [habit]); var b = HabitLog(habits: [habit])
        a.setDone(true, habitId: habit.id, on: DayKey(rawValue: "2026-09-01"), calendar: cal)
        b.setDone(true, habitId: habit.id, on: DayKey(rawValue: "2026-09-02"), calendar: cal)
        let merged = HabitLog.merge(local: a, remote: b)
        #expect(merged.isDone(habit.id, on: DayKey(rawValue: "2026-09-01")))
        #expect(merged.isDone(habit.id, on: DayKey(rawValue: "2026-09-02")))
        #expect(!merged.isDone(habit.id, on: DayKey(rawValue: "2026-09-03")))
    }
}

struct WaterTests {
    @Test func countsStreakAndMerge() {
        var log = WaterLog(goalCups: 2)
        let d1 = DayKey(rawValue: "2026-09-01"), d2 = DayKey(rawValue: "2026-09-02"), d3 = DayKey(rawValue: "2026-09-03")
        log.add(1, on: d1, calendar: cal); log.add(1, on: d1, calendar: cal)
        log.add(3, on: d2, calendar: cal)
        #expect(log.cups(on: d1) == 2 && log.cups(on: d2) == 3 && log.cups(on: d3) == 0)
        #expect(log.streak(endingOn: d3, calendar: cal) == 2)   // today empty, yesterday+day before hit goal
        #expect(log.months[MonthKey(rawValue: "2026-09")]?.count == 30)
        var other = WaterLog(goalCups: 2)
        other.add(5, on: d1, calendar: cal)
        let merged = WaterLog.merge(local: log, remote: other)
        #expect(merged.cups(on: d1) == 5 && merged.cups(on: d2) == 3)
        log.add(-9, on: d1, calendar: cal)
        #expect(log.cups(on: d1) == 0)
    }
}

struct PRTests {
    @Test func epleyAndNewRecords() {
        #expect(PRDetector.estimatedOneRM(weight: 100, reps: 1) == 100)
        #expect(abs(PRDetector.estimatedOneRM(weight: 100, reps: 10) - 133.33) < 0.01)
        let session = WorkoutSession(name: "Push", sets: [
            SetEntry(exerciseId: "bench_press", reps: 10, weight: 60, isWarmup: true),
            SetEntry(exerciseId: "bench_press", reps: 5, weight: 100),
            SetEntry(exerciseId: "bench_press", reps: 3, weight: 110),
            SetEntry(exerciseId: "squat", reps: 5, weight: 120)
        ])
        let existing = ["squat": PersonalRecord(weight: 140, reps: 5, estimatedOneRM: 163.3, date: Date(), sessionId: UUID())]
        let prs = PRDetector.newRecords(in: session, existing: existing)
        #expect(prs["squat"] == nil)
        #expect(prs["bench_press"]?.weight == 110)
        #expect(session.totalVolume == 500 + 330 + 600)
    }
}

struct BillSplitTests {
    @Test func splitsAndRounds() {
        let r = BillSplitCalculator.split(subtotal: 100, tax: 8, tipPercent: 18, people: 3)
        #expect(r.tip == 18 && r.total == 126)
        #expect(r.perPerson == 42)
        let up = BillSplitCalculator.split(subtotal: 100, tax: 8.25, tipPercent: 20, tipOnPreTax: false, people: 4, roundUp: true)
        #expect(up.tip == Decimal(string: "21.65"))
        #expect(up.perPerson == 33)   // 129.90 / 4 = 32.475 → 33
        #expect(BillSplitCalculator.split(subtotal: 10, tipPercent: 0, people: 0).perPerson == 10)
    }
}

struct CalorieTests {
    @Test func totalsRecentsAndMerge() {
        var settings = CalorieSettings()
        var month = CalorieMonth()
        let day = DayKey(rawValue: "2026-09-13")
        let coffee = FoodEntry(name: "Coffee", kcal: 5)
        let eggs = FoodEntry(name: "Eggs", kcal: 210, protein: 18, carbs: 1, fat: 15)
        month.add(coffee, on: day); month.add(eggs, on: day)
        settings.noteRecent(coffee); settings.noteRecent(eggs); settings.noteRecent(coffee)
        #expect(month.totals(on: day) == MacroTotals(kcal: 215, protein: 18, carbs: 1, fat: 15))
        #expect(settings.recentFoods.map(\.name) == ["Coffee", "Eggs"])
        var remote = CalorieMonth()
        remote.add(FoodEntry(name: "Apple", kcal: 95), on: day)
        remote.add(eggs, on: day)   // same id, must not duplicate
        #expect(CalorieMonth.merge(local: month, remote: remote).entries(on: day).count == 3)
        month.remove(id: coffee.id, on: day)
        #expect(month.entries(on: day).count == 1)
    }
}

struct PreferencesTests {
    @Test func orderingHonoursPrefsAndRegistry() {
        let a = FavWidgetDescriptor(id: "a", title: "", subtitle: "", symbolName: "", accentHex: "#000000", category: .health)
        let b = FavWidgetDescriptor(id: "b", title: "", subtitle: "", symbolName: "", accentHex: "#000000", category: .health)
        let c = FavWidgetDescriptor(id: "c", title: "", subtitle: "", symbolName: "", accentHex: "#000000", category: .health, defaultEnabled: false)
        var prefs = WidgetPreferences(order: ["b", "zzz", "b"], disabled: ["a"])
        #expect(WidgetOrdering.all(prefs: prefs, descriptors: [a, b, c]).map(\.id) == ["b", "a", "c"])
        #expect(WidgetOrdering.visible(prefs: prefs, descriptors: [a, b, c]).map(\.id) == ["b"])
        prefs.setEnabled(true, id: "c"); prefs.setEnabled(true, id: "a")
        #expect(WidgetOrdering.visible(prefs: prefs, descriptors: [a, b, c]).map(\.id) == ["b", "c", "a"])
        let merged = WidgetPreferences.merge(local: prefs, remote: WidgetPreferences(seenHints: ["x"]))
        #expect(merged.seenHints == ["x"] && merged.order == prefs.order)
    }
}

import Foundation

public enum StreakCalculator {
    /// Days in a row the habit was done on its due days, ending today (or
    /// yesterday when today is still open). Non-due days neither count nor
    /// break the streak.
    public static func current(log: HabitLog, habit: Habit, today: DayKey, calendar: Calendar = .current) -> Int {
        var day = today
        var streak = 0
        let floor = DayKey(habit.createdAt, calendar: calendar)
        // Today not yet done doesn't break the streak; start from yesterday.
        if habit.schedule.isDue(on: day, calendar: calendar), !log.isDone(habit.id, on: day) {
            day = day.adding(days: -1, calendar: calendar)
        }
        var guardCount = 0
        while day >= floor.adding(days: -1, calendar: calendar), guardCount < 3660 {
            guardCount += 1
            if habit.schedule.isDue(on: day, calendar: calendar) {
                if log.isDone(habit.id, on: day) { streak += 1 } else { break }
            }
            day = day.adding(days: -1, calendar: calendar)
        }
        return streak
    }

    /// Longest run ever, scanning from the habit's creation to today.
    public static func best(log: HabitLog, habit: Habit, today: DayKey, calendar: Calendar = .current) -> Int {
        var day = DayKey(habit.createdAt, calendar: calendar)
        var best = 0
        var run = 0
        var guardCount = 0
        while day <= today, guardCount < 3660 {
            guardCount += 1
            if habit.schedule.isDue(on: day, calendar: calendar) {
                if log.isDone(habit.id, on: day) {
                    run += 1
                    best = max(best, run)
                } else if day != today {
                    run = 0
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return best
    }
}

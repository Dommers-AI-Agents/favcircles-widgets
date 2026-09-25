import SwiftUI
import FavWidgetsCore

/// Daily habits with schedules and streaks. Single document for all time
/// (`HabitLog`); archiving keeps every completion.
public struct HabitWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "habits",
        title: "Habits",
        subtitle: "Daily check-ins and streaks",
        symbolName: "checkmark.circle.fill",
        accentHex: "#38A169",
        category: .health,
        storage: .single,
        shareBlurb: "Keep daily habits with one-tap check-ins and streaks."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(HabitCardView(context: context, state: context.state(HabitLog.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(HabitFullView(context: context, state: context.state(HabitLog.self)))
    }
}

/// The fixed set of SF Symbols a habit can wear.
enum HabitSymbols {
    static let all = [
        "checkmark.circle", "drop.fill", "figure.walk", "figure.run", "dumbbell.fill",
        "book.fill", "bed.double.fill", "leaf.fill", "brain.head.profile", "pencil",
        "fork.knife", "sun.max.fill", "moon.stars.fill", "heart.fill", "music.note", "pills.fill"
    ]
}

/// The schedule choices in the editor; `custom` exposes the seven toggles.
enum HabitSchedulePreset: String, CaseIterable, Identifiable {
    case daily = "Every day"
    case weekdays = "Weekdays"
    case weekends = "Weekends"
    case custom = "Custom"

    var id: String { rawValue }

    static let weekdaySet: Set<Int> = [2, 3, 4, 5, 6]
    static let weekendSet: Set<Int> = [1, 7]

    init(schedule: HabitSchedule) {
        switch schedule {
        case .daily: self = .daily
        case .weekdays(let days):
            if days == Self.weekdaySet { self = .weekdays }
            else if days == Self.weekendSet { self = .weekends }
            else { self = .custom }
        }
    }
}

enum HabitFormatting {
    static func monthTitle(_ month: MonthKey, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month.day(1).date(calendar: calendar))
    }

    /// "Every day", "Weekdays", "Mon, Wed, Fri" …
    static func scheduleDescription(_ schedule: HabitSchedule, calendar: Calendar) -> String {
        switch HabitSchedulePreset(schedule: schedule) {
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .custom:
            guard case .weekdays(let days) = schedule else { return "Custom" }
            let symbols = calendar.shortWeekdaySymbols
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }.filter { days.contains($0) }
            if ordered.isEmpty { return "Never" }
            return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// Best streak among the given habits (0 when none).
    static func bestStreak(in log: HabitLog, habits: [Habit], today: DayKey, calendar: Calendar) -> Int {
        habits.map { StreakCalculator.best(log: log, habit: $0, today: today, calendar: calendar) }.max() ?? 0
    }
}

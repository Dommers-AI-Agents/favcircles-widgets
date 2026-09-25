import SwiftUI
import FavWidgetsCore

/// Calories: quick-add meals and macros against a daily goal. Settings +
/// recents live in the `calories` document; each month's entries in
/// `calories_yyyy-MM`.
public struct CalorieWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "calories",
        title: "Calories",
        subtitle: "Quick-add meals and macros",
        symbolName: "flame.fill",
        accentHex: "#FF8500",
        category: .health,
        storage: .monthly,
        shareBlurb: "Log meals and macros in a couple of taps."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(CalorieCardView(
            context: context,
            settings: context.state(CalorieSettings.self),
            month: context.month(CalorieMonth.self, context.today.monthKey)
        ))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(CalorieFullView(context: context, settings: context.state(CalorieSettings.self)))
    }
}

// MARK: - Shared formatting

enum CalorieFormat {
    static func kcal(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func grams(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))g" : "\(rounded)g"
    }

    /// "P 80g · C 120g · F 40g"; nil when no macros were logged.
    static func macroLine(_ totals: MacroTotals) -> String? {
        guard totals.protein > 0 || totals.carbs > 0 || totals.fat > 0 else { return nil }
        return "P \(grams(totals.protein)) · C \(grams(totals.carbs)) · F \(grams(totals.fat))"
    }

    static func dayTitle(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1, calendar: calendar) { return "Yesterday" }
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate(day.year == today.year ? "EEE d MMM" : "EEE d MMM yyyy")
        return f.string(from: day.date(calendar: calendar))
    }

    static func weekdayLetter(_ day: DayKey, calendar: Calendar) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = day.weekday(calendar: calendar) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// A timestamp inside `day`: now for today, otherwise the day at the
    /// current time-of-day so entries added to a past day still order by
    /// when they were logged.
    static func loggedAt(for day: DayKey, today: DayKey, calendar: Calendar) -> Date {
        let now = Date()
        if day == today { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0,
                             of: day.date(calendar: calendar)) ?? day.date(calendar: calendar)
    }
}

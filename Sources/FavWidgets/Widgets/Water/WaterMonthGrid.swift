import SwiftUI
import FavWidgetsCore

/// Calendar-shaped grid of small squares, each tinted by that day's
/// fraction of the goal. Weeks start on the calendar's first weekday.
struct WaterMonthGrid: View {
    let context: WidgetContext
    let model: WaterLog
    let month: MonthKey

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    static func tint(fraction: Double, accent: Color, theme: WidgetTheme) -> Color {
        guard fraction > 0 else { return theme.tertiaryBackground }
        return accent.opacity(0.2 + 0.8 * min(1, fraction))
    }

    var body: some View {
        let theme = context.theme
        let calendar = context.calendar
        let goal = max(1, model.goalCups)
        let dayCount = month.dayCount(calendar: calendar)
        let leading = (month.day(1).weekday(calendar: calendar) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortWeekdaySymbols
        let today = context.today

        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let weekdayIndex = (calendar.firstWeekday - 1 + offset) % 7
                    Text(symbols[weekdayIndex])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
                ForEach(1...dayCount, id: \.self) { dayNumber in
                    let day = month.day(dayNumber)
                    let cups = model.cups(on: day)
                    let fraction = Double(cups) / Double(goal)
                    let isFuture = day > today
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isFuture ? theme.tertiaryBackground.opacity(0.4) : Self.tint(fraction: fraction, accent: context.accent, theme: theme))
                        if day == today {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(theme.label.opacity(0.6), lineWidth: 1.5)
                        }
                        Text("\(dayNumber)")
                            .font(.system(size: 10, weight: day == today ? .bold : .regular))
                            .foregroundStyle(fraction >= 0.6 && !isFuture ? Color.white : theme.secondaryLabel)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.rawValue): \(cups) cups")
                }
            }
        }
    }
}

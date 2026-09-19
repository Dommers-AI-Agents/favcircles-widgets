import SwiftUI
import FavWidgetsCore

/// Workouts ("Strong-lite"): routines, an in-progress session that lives in
/// the settings document until finished, cardio alongside the sets, monthly
/// history, running PRs, and workouts shared with the Inner Circle.
public struct WorkoutWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "workouts",
        title: "Workouts",
        subtitle: "Log sets, reps and PRs",
        symbolName: "dumbbell.fill",
        accentHex: "#3182CE",
        category: .fitness,
        storage: .monthly,
        // 2 (2026-09-19): body profile, cardio entries, exercise photos.
        schemaVersion: 2
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WorkoutCardView(
            context: context,
            settings: context.state(WorkoutSettings.self),
            currentMonth: context.month(WorkoutMonth.self, context.currentMonth),
            previousMonth: context.month(WorkoutMonth.self, context.currentMonth.previous)
        ))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(WorkoutFullView(context: context, settings: context.state(WorkoutSettings.self)))
    }
}

// MARK: - Formatting

enum WorkoutFormat {
    /// "12:34" under an hour, "1:02:03" past it.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1h 02m" / "42m" for history rows.
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    static func weight(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return rounded.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func set(_ weight: Double, _ reps: Int) -> String {
        "\(self.weight(weight)) × \(reps)"
    }

    static func volume(_ value: Double, unit: WeightUnit) -> String {
        "\(Int(value.rounded()).formatted(.number.grouping(.automatic))) \(unit.label)"
    }

    static func relativeDay(_ date: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<0: return "later"
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return shortDate(date, calendar: calendar)
        }
    }

    static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }

    static func monthTitle(_ month: MonthKey, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: month.day(1).date(calendar: calendar))
    }

    static func parseDecimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0, value.isFinite else { return nil }
        return value
    }

    static func parseInt(_ text: String) -> Int? {
        guard let value = parseDecimal(text) else { return nil }
        return Int(value.rounded())
    }

    static func decimalText(_ value: Double) -> String {
        value == 0 ? "" : weight(value)
    }
}

extension View {
    /// A "Done" button above the numeric keyboard (iOS only; macOS has no
    /// software keyboard). Applied once per screen so it isn't duplicated.
    @ViewBuilder
    func workoutKeyboardDoneBar() -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.system(size: 16, weight: .semibold))
            }
        }
        #else
        self
        #endif
    }
}

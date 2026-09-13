import SwiftUI
import FavWidgetsCore

/// Full screen: today's count with +/−, streak, last-7-days chart, a month
/// grid with prev/next navigation, and settings (goal, cup size).
struct WaterFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WaterLog>

    /// Month shown in the grid; `nil` means the current month.
    @State private var shownMonth: MonthKey?

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WidgetSyncBadge(state: state.syncState, theme: theme)
                todaySection(theme: theme)
                weekSection(theme: theme)
                monthSection(theme: theme)
                settingsSection(theme: theme)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await state.loadIfNeeded() }
    }

    // MARK: - Today

    @ViewBuilder
    private func todaySection(theme: WidgetTheme) -> some View {
        let model = state.model
        let today = context.today
        let cups = model.cups(on: today)
        let goal = max(1, model.goalCups)
        let streak = model.streak(endingOn: today, calendar: context.calendar)

        VStack(spacing: 12) {
            HStack(spacing: 28) {
                roundButton(symbol: "minus", enabled: cups > 0, theme: theme) {
                    state.update { $0.add(-1, on: today, calendar: context.calendar) }
                    context.host.haptic(.light)
                    context.track("water_remove_cup")
                }
                VStack(spacing: 2) {
                    Text("\(cups)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(cups >= goal ? context.accent : theme.label)
                        .monospacedDigit()
                    Text("of \(goal) cups · \(model.cupMl) ml each")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .frame(minWidth: 120)
                roundButton(symbol: "plus", enabled: true, theme: theme) {
                    state.update { $0.add(1, on: today, calendar: context.calendar) }
                    context.host.haptic(.light)
                    context.track("water_add_cup")
                }
            }
            .frame(maxWidth: .infinity)

            WidgetUI.progressBar(fraction: Double(cups) / Double(goal), color: context.accent, theme: theme)

            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? theme.warning : theme.secondaryLabel)
                Text(streakText(streak: streak, reached: cups >= goal))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.label)
                Spacer()
                Text("\(cups * model.cupMl) ml today")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
    }

    private func streakText(streak: Int, reached: Bool) -> String {
        if reached { return streak == 1 ? "Goal reached · 1-day streak" : "Goal reached · \(streak)-day streak" }
        if streak == 0 { return "Hit your goal to start a streak" }
        return "\(streak)-day streak — keep it going today"
    }

    private func roundButton(symbol: String, enabled: Bool, theme: WidgetTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(enabled ? .white : theme.secondaryLabel)
                .frame(width: 56, height: 56)
                .background(Circle().fill(enabled ? context.accent : theme.tertiaryBackground))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Add a cup" : "Remove a cup")
    }

    // MARK: - Last 7 days

    @ViewBuilder
    private func weekSection(theme: WidgetTheme) -> some View {
        let model = state.model
        let goal = max(1, model.goalCups)
        let days = (0..<7).reversed().map { context.today.adding(days: -$0, calendar: context.calendar) }
        let symbols = context.calendar.veryShortWeekdaySymbols

        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Last 7 days", theme: theme)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.rawValue) { day in
                    let cups = model.cups(on: day)
                    let fraction = min(1, Double(cups) / Double(goal))
                    VStack(spacing: 4) {
                        Text(cups > 0 ? "\(cups)" : "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.secondaryLabel)
                            .frame(height: 12)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(theme.tertiaryBackground)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(cups >= goal ? context.accent : context.accent.opacity(0.6))
                                .frame(height: max(fraction > 0 ? 4 : 0, fraction * 72))
                        }
                        .frame(height: 72)
                        Text(symbols[(day.weekday(calendar: context.calendar) - 1 + symbols.count) % symbols.count])
                            .font(.system(size: 11, weight: day == context.today ? .bold : .regular))
                            .foregroundStyle(day == context.today ? theme.label : theme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.rawValue): \(cups) of \(goal) cups")
                }
            }
        }
    }

    // MARK: - Month grid

    @ViewBuilder
    private func monthSection(theme: WidgetTheme) -> some View {
        let month = shownMonth ?? context.currentMonth
        let isCurrent = month == context.currentMonth
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header(isCurrent ? "This month" : monthTitle(month), theme: theme)
                Button {
                    shownMonth = month.previous
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(context.accent)
                .accessibilityLabel("Previous month")
                Button {
                    shownMonth = isCurrent ? nil : month.next
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isCurrent ? theme.secondaryLabel.opacity(0.4) : context.accent)
                .disabled(isCurrent)
                .accessibilityLabel("Next month")
            }
            WaterMonthGrid(context: context, model: state.model, month: month)
            HStack(spacing: 12) {
                legendSwatch(fraction: 0, label: "None", theme: theme)
                legendSwatch(fraction: 0.5, label: "Halfway", theme: theme)
                legendSwatch(fraction: 1, label: "Goal", theme: theme)
                Spacer()
                Text(monthTotal(month))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    private func legendSwatch(fraction: Double, label: String, theme: WidgetTheme) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(WaterMonthGrid.tint(fraction: fraction, accent: context.accent, theme: theme))
                .frame(width: 12, height: 12)
            Text(label).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private func monthTotal(_ month: MonthKey) -> String {
        let counts = state.model.months[month] ?? []
        let cups = counts.reduce(0, +)
        let goalDays = counts.filter { $0 >= max(1, state.model.goalCups) }.count
        return "\(cups) cups · \(goalDays) goal days"
    }

    private func monthTitle(_ month: MonthKey) -> String {
        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month.day(1).date(calendar: context.calendar))
    }

    // MARK: - Settings

    @ViewBuilder
    private func settingsSection(theme: WidgetTheme) -> some View {
        let goalBinding = Binding<Int>(
            get: { state.model.goalCups },
            set: { value in
                let clamped = max(1, min(20, value))
                state.update { $0.goalCups = clamped }
                context.track("water_goal_changed", ["goal": "\(clamped)"])
            }
        )
        let cupBinding = Binding<Int>(
            get: { state.model.cupMl },
            set: { value in
                state.update { $0.cupMl = value }
                context.track("water_cup_size_changed", ["ml": "\(value)"])
            }
        )
        VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Settings", theme: theme)
            VStack(spacing: 0) {
                HStack {
                    Text("Daily goal").foregroundStyle(theme.label)
                    Spacer()
                    Stepper("\(state.model.goalCups) cups", value: goalBinding, in: 1...20)
                        .fixedSize()
                        .foregroundStyle(theme.secondaryLabel)
                }
                .padding(.vertical, 10)
                Divider().overlay(theme.separator)
                HStack {
                    Text("Cup size").foregroundStyle(theme.label)
                    Spacer()
                    Picker("Cup size", selection: cupBinding) {
                        ForEach(WaterCupSizes.all, id: \.self) { ml in
                            Text("\(ml) ml").tag(ml)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(context.accent)
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
            Text("Changing the goal applies to every day, including past streaks.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
        }
    }
}

import SwiftUI
import FavWidgetsCore

/// Full screen: today's due habits with checks and streaks, habits not due
/// today, add-habit form, per-habit detail, and the archived list.
struct HabitFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<HabitLog>

    @State private var isAdding = false
    @State private var selectedHabitId: UUID?

    private struct SelectedHabit: Identifiable { let id: UUID }

    var body: some View {
        let theme = context.theme
        let model = state.model
        let today = context.today
        let active = model.activeHabits
        let due = active.filter { $0.schedule.isDue(on: today, calendar: context.calendar) }
        let notDue = active.filter { !$0.schedule.isDue(on: today, calendar: context.calendar) }
        let archived = model.habits.filter(\.isArchived)
        let counts = model.doneCount(on: today, calendar: context.calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WidgetSyncBadge(state: state.syncState, theme: theme)

                if active.isEmpty {
                    emptyState(theme: theme)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            WidgetUI.header("Today", theme: theme)
                            Text(due.isEmpty ? "Nothing due" : "\(counts.done) / \(counts.due) done")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(counts.due > 0 && counts.done == counts.due ? context.accent : theme.secondaryLabel)
                        }
                        if counts.due > 0 {
                            WidgetUI.progressBar(fraction: Double(counts.done) / Double(counts.due), color: context.accent, theme: theme)
                        }
                        if due.isEmpty {
                            Text("No habits are scheduled for today. Enjoy the day off!")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.secondaryLabel)
                        } else {
                            rowGroup(theme: theme) {
                                ForEach(due) { habit in
                                    habitRow(habit, dueToday: true, theme: theme)
                                }
                            }
                        }
                    }

                    if !notDue.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            WidgetUI.header("Not today", theme: theme)
                            rowGroup(theme: theme) {
                                ForEach(notDue) { habit in
                                    habitRow(habit, dueToday: false, theme: theme).opacity(0.55)
                                }
                            }
                        }
                    }
                }

                WidgetUI.primaryButton("Add habit", color: context.accent) {
                    isAdding = true
                }

                if !archived.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        WidgetUI.header("Archived", theme: theme)
                        rowGroup(theme: theme) {
                            ForEach(archived) { habit in
                                archivedRow(habit, theme: theme)
                            }
                        }
                        Text("Archived habits keep their history and can be restored any time.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await state.loadIfNeeded() }
        .sheet(isPresented: $isAdding) {
            HabitEditorView(context: context, state: state, habitId: nil)
        }
        .sheet(item: Binding<SelectedHabit?>(
            get: { selectedHabitId.map(SelectedHabit.init) },
            set: { selectedHabitId = $0?.id }
        )) { selected in
            HabitDetailView(context: context, state: state, habitId: selected.id)
        }
    }

    // MARK: - Pieces

    private func emptyState(theme: WidgetTheme) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(context.accent)
            Text("Build a streak")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.label)
            Text("Add a habit you want to do every day, on weekdays, or on the days you choose. Check it off from the Widgets tab.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func rowGroup<Content: View>(theme: WidgetTheme, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
    }

    private func habitRow(_ habit: Habit, dueToday: Bool, theme: WidgetTheme) -> some View {
        let today = context.today
        let done = state.model.isDone(habit.id, on: today)
        let streak = StreakCalculator.current(log: state.model, habit: habit, today: today, calendar: context.calendar)
        return HStack(spacing: 12) {
            Button {
                selectedHabitId = habit.id
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: habit.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(context.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.label)
                            .strikethrough(done && dueToday, color: theme.secondaryLabel)
                        Text(dueToday
                             ? (streak > 0 ? "🔥 \(streak)" : "Start your streak")
                             : HabitFormatting.scheduleDescription(habit.schedule, calendar: context.calendar))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if dueToday {
                Button {
                    state.update { $0.toggle(habit.id, on: today, calendar: context.calendar) }
                    context.host.haptic(done ? .light : .success)
                    context.track("habit_toggled", ["done": done ? "false" : "true"])
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(done ? context.accent : theme.secondaryLabel.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "Mark \(habit.name) not done" : "Mark \(habit.name) done")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func archivedRow(_ habit: Habit, theme: WidgetTheme) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedHabitId = habit.id
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: habit.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                        .frame(width: 28)
                    Text(habit.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Restore") {
                restore(habit.id)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(context.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func restore(_ id: UUID) {
        state.update { model in
            if let index = model.habits.firstIndex(where: { $0.id == id }) {
                model.habits[index].archivedAt = nil
            }
        }
        context.host.haptic(.light)
        context.track("habit_restored")
    }
}

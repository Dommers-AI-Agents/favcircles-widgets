import SwiftUI
import FavWidgetsCore

/// One habit: streaks, a month grid of completions with prev/next, edit,
/// and archive / restore. Never deletes anything.
struct HabitDetailView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<HabitLog>
    let habitId: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var shownMonth: MonthKey?
    @State private var isEditing = false
    @State private var confirmArchive = false

    private var habit: Habit? { state.model.habits.first { $0.id == habitId } }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            Group {
                if let habit {
                    content(habit: habit, theme: theme)
                } else {
                    Text("This habit is no longer available.")
                        .foregroundStyle(theme.secondaryLabel)
                        .padding()
                }
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(habit?.name ?? "Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") { isEditing = true }
                        .disabled(habit == nil)
                }
            }
        }
        .tint(context.accent)
        .sheet(isPresented: $isEditing) {
            HabitEditorView(context: context, state: state, habitId: habitId)
        }
    }

    @ViewBuilder
    private func content(habit: Habit, theme: WidgetTheme) -> some View {
        let today = context.today
        let current = StreakCalculator.current(log: state.model, habit: habit, today: today, calendar: context.calendar)
        let best = StreakCalculator.best(log: state.model, habit: habit, today: today, calendar: context.calendar)
        let month = shownMonth ?? context.currentMonth
        let isCurrentMonth = month == context.currentMonth

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WidgetSyncBadge(state: state.syncState, theme: theme)

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent.opacity(0.15))
                        Image(systemName: habit.symbolName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(context.accent)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(habit.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.label)
                        Text(HabitFormatting.scheduleDescription(habit.schedule, calendar: context.calendar))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryLabel)
                        if habit.isArchived {
                            Text("Archived")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.warning)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    statTile(value: "🔥 \(current)", label: "Current streak", theme: theme)
                    statTile(value: "\(best)", label: "Best streak", theme: theme)
                    statTile(value: "\(totalCompletions(habit))", label: "Total", theme: theme)
                }

                if habit.schedule.isDue(on: today, calendar: context.calendar), !habit.isArchived {
                    let done = state.model.isDone(habit.id, on: today)
                    WidgetUI.primaryButton(done ? "Done today ✓ — tap to undo" : "Mark done today", color: done ? theme.success : context.accent) {
                        state.update { $0.toggle(habit.id, on: today, calendar: context.calendar) }
                        context.host.haptic(done ? .light : .success)
                        context.track("habit_toggled", ["done": done ? "false" : "true"])
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        WidgetUI.header(HabitFormatting.monthTitle(month, calendar: context.calendar), theme: theme)
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
                            shownMonth = isCurrentMonth ? nil : month.next
                        } label: {
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isCurrentMonth ? theme.secondaryLabel.opacity(0.4) : context.accent)
                        .disabled(isCurrentMonth)
                        .accessibilityLabel("Next month")
                    }
                    HabitMonthGrid(context: context, state: state, habit: habit, month: month)
                    Text("Tap a past day to fix a missed check-in.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                }

                archiveSection(habit: habit, theme: theme)
            }
            .padding(16)
        }
    }

    private func statTile(value: String, label: String, theme: WidgetTheme) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
    }

    private func totalCompletions(_ habit: Habit) -> Int {
        (state.model.completions[habit.id.uuidString] ?? [:]).values.reduce(0) { $0 + $1.filter { $0 == "1" }.count }
    }

    @ViewBuilder
    private func archiveSection(habit: Habit, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if habit.isArchived {
                Button {
                    setArchived(false)
                } label: {
                    Label("Restore habit", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    confirmArchive = true
                } label: {
                    Label("Archive habit", systemImage: "archivebox")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.danger.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Archive \(habit.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
                    Button("Archive") { setArchived(true) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It leaves your daily list. Every check-in is kept and you can restore it any time.")
                }
            }
            Text("Archiving never deletes your history.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
                .frame(maxWidth: .infinity)
        }
    }

    private func setArchived(_ archived: Bool) {
        state.update { model in
            guard let index = model.habits.firstIndex(where: { $0.id == habitId }) else { return }
            model.habits[index].archivedAt = archived ? Date() : nil
        }
        context.host.haptic(.light)
        context.track(archived ? "habit_archived" : "habit_restored")
    }
}

/// Calendar grid for one habit: filled squares for completed days, outlined
/// for due-but-missed days, faint for days it wasn't due.
struct HabitMonthGrid: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<HabitLog>
    let habit: Habit
    let month: MonthKey

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    var body: some View {
        let theme = context.theme
        let calendar = context.calendar
        let today = context.today
        let dayCount = month.dayCount(calendar: calendar)
        let leading = (month.day(1).weekday(calendar: calendar) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortWeekdaySymbols
        let created = DayKey(habit.createdAt, calendar: calendar)

        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(symbols[(calendar.firstWeekday - 1 + offset) % 7])
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
                    let done = state.model.isDone(habit.id, on: day)
                    let due = habit.schedule.isDue(on: day, calendar: calendar)
                    let isFuture = day > today
                    let beforeCreation = day < created
                    let editable = !isFuture && !beforeCreation && !habit.isArchived
                    Button {
                        guard editable else { return }
                        state.update { $0.toggle(habit.id, on: day, calendar: calendar) }
                        context.host.haptic(.selection)
                        context.track("habit_backfilled", ["done": done ? "false" : "true"])
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(done ? context.accent : (due && editable ? theme.tertiaryBackground : theme.tertiaryBackground.opacity(0.35)))
                            if day == today {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(theme.label.opacity(0.6), lineWidth: 1.5)
                            }
                            Text("\(dayNumber)")
                                .font(.system(size: 10, weight: day == today ? .bold : .regular))
                                .foregroundStyle(done ? Color.white : theme.secondaryLabel.opacity(editable ? 1 : 0.5))
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                    .disabled(!editable)
                    .accessibilityLabel("\(day.rawValue): \(done ? "done" : (due ? "not done" : "not scheduled"))")
                }
            }
        }
    }
}

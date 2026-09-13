import SwiftUI
import FavWidgetsCore

/// Add / edit form: name, symbol, schedule. Drafts live locally and commit
/// as one `state.update` on Save.
struct HabitEditorView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<HabitLog>
    /// `nil` adds a new habit; otherwise edits the existing one.
    let habitId: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbolName = HabitSymbols.all[0]
    @State private var preset: HabitSchedulePreset = .daily
    @State private var customDays: Set<Int> = HabitSchedulePreset.weekdaySet
    @State private var loadedDraft = false

    private var isEditing: Bool { habitId != nil }

    private var schedule: HabitSchedule {
        switch preset {
        case .daily: return .daily
        case .weekdays: return .weekdays(HabitSchedulePreset.weekdaySet)
        case .weekends: return .weekdays(HabitSchedulePreset.weekendSet)
        case .custom: return .weekdays(customDays)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (preset != .custom || !customDays.isEmpty)
    }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetUI.header("Name", theme: theme)
                        TextField("Drink water, Read 10 pages…", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17))
                            .foregroundStyle(theme.label)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                            .submitLabel(.done)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        WidgetUI.header("Icon", theme: theme)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(HabitSymbols.all, id: \.self) { symbol in
                                Button {
                                    symbolName = symbol
                                    context.host.haptic(.selection)
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(symbol == symbolName ? Color.white : context.accent)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(symbol == symbolName ? context.accent : context.accent.opacity(0.12))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                                .accessibilityAddTraits(symbol == symbolName ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        WidgetUI.header("Schedule", theme: theme)
                        Picker("Schedule", selection: $preset) {
                            ForEach(HabitSchedulePreset.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        if preset == .custom {
                            dayToggles(theme: theme)
                            if customDays.isEmpty {
                                Text("Pick at least one day.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.warning)
                            }
                        } else {
                            Text(HabitFormatting.scheduleDescription(schedule, calendar: context.calendar))
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryLabel)
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(isEditing ? "Edit Habit" : "New Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .tint(context.accent)
        .onAppear(perform: loadDraft)
    }

    private func dayToggles(theme: WidgetTheme) -> some View {
        let calendar = context.calendar
        let symbols = calendar.shortWeekdaySymbols
        let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { weekday in
                let on = customDays.contains(weekday)
                Button {
                    if on { customDays.remove(weekday) } else { customDays.insert(weekday) }
                    context.host.haptic(.selection)
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color.white : theme.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Capsule().fill(on ? context.accent : theme.tertiaryBackground))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func loadDraft() {
        guard !loadedDraft else { return }
        loadedDraft = true
        guard let habitId, let habit = state.model.habits.first(where: { $0.id == habitId }) else { return }
        name = habit.name
        symbolName = habit.symbolName
        preset = HabitSchedulePreset(schedule: habit.schedule)
        if case .weekdays(let days) = habit.schedule { customDays = days }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }
        let newSchedule = schedule
        if let habitId {
            state.update { model in
                guard let index = model.habits.firstIndex(where: { $0.id == habitId }) else { return }
                model.habits[index].name = trimmed
                model.habits[index].symbolName = symbolName
                model.habits[index].schedule = newSchedule
            }
            context.track("habit_edited")
        } else {
            let habit = Habit(name: trimmed, symbolName: symbolName, schedule: newSchedule)
            state.update { $0.habits.append(habit) }
            context.track("habit_added", ["schedule": preset.rawValue])
        }
        context.host.haptic(.success)
        dismiss()
    }
}

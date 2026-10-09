import FavWidgetsCore

extension HabitWidget {
    /// "3 of 4 habits done today" and the best streak — counts only, no habit names.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let state = context.state(HabitLog.self)
        await state.loadIfNeeded()
        let active = state.model.habits.filter { !$0.isArchived }
        guard !active.isEmpty else { return nil }
        let counts = state.model.doneCount(on: context.today, calendar: context.calendar)
        return .habits(done: counts.done, due: counts.due,
                       bestStreak: HabitFormatting.bestStreak(in: state.model, habits: active, today: context.today, calendar: context.calendar))
    }
}

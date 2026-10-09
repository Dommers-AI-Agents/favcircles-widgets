import FavWidgetsCore

extension MotivationWidget {
    /// Coach Mane's line right now, and the streak.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let state = context.state(MotivationLog.self)
        await state.loadIfNeeded()
        return .motivation(line: state.model.currentLine(), streak: state.model.streak(endingOn: context.today, calendar: context.calendar))
    }
}

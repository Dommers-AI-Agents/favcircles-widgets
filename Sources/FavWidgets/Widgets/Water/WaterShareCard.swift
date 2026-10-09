import FavWidgetsCore

extension WaterWidget {
    /// "5 of 8 cups today" / "Hit my water goal", with the streak.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let state = context.state(WaterLog.self)
        await state.loadIfNeeded()
        let m = state.model
        return .water(cups: m.cups(on: context.today), goal: max(1, m.goalCups),
                      streak: m.streak(endingOn: context.today, calendar: context.calendar))
    }
}

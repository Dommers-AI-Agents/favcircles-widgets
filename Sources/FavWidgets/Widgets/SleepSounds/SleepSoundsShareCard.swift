import FavWidgetsCore

extension SleepSoundsWidget {
    /// "Falling asleep to Rain on a tent" and nights this month.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let settings = context.state(SleepSoundsSettings.self)
        let month = context.month(SleepSoundsMonth.self, context.currentMonth)
        await settings.loadIfNeeded()
        await month.loadIfNeeded()
        return .sleepSounds(mix: settings.model.startingName, nightsThisMonth: month.model.sessions.count)
    }
}

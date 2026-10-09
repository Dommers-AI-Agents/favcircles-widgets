import FavWidgetsCore

extension NextBarWidget {
    /// Today's pick only; an old pick isn't a plan anymore.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let state = context.state(NextBarSettings.self)
        await state.loadIfNeeded()
        guard let pick = state.model.currentPick, pick.day == context.today else { return nil }
        return .nextBar(name: pick.name,
                        attribution: NextBarFormat.attribution(pick.source, savedBy: pick.savedByName, savers: pick.savers),
                        distance: pick.distanceMeters > 0 ? NextBarFormat.distance(pick.distanceMeters) : nil)
    }
}

import FavWidgetsCore

extension WhatToEatWidget {
    /// The current craving: cuisine and dish.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let state = context.state(WhatToEatSettings.self)
        await state.loadIfNeeded()
        guard let cuisine = state.model.currentCuisine else { return nil }
        return .whatToEat(emoji: cuisine.emoji, cuisine: cuisine.name, dish: state.model.currentDish)
    }
}

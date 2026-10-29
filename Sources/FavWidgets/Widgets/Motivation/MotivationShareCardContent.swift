import FavWidgetsCore

extension MotivationWidget {
    /// Coach Mane's line right now, and the streak, drawn as the same coach
    /// card Send-to-someone uses, so both shares look alike.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let state = context.state(MotivationLog.self)
        await state.loadIfNeeded()
        let line = state.model.currentLine()
        var content = WidgetShareCardContent.motivation(line: line, streak: state.model.streak(endingOn: context.today, calendar: context.calendar))
        content.cardJPEG = MotivationShareCard.jpeg(line: line, accent: context.accent)
        return content
    }
}

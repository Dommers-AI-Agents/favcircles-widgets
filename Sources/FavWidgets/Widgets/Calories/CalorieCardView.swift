import SwiftUI
import FavWidgetsCore

/// Card: today's ring, "1,240 / 2,000 kcal", macro line, "+ Add".
/// Renders from whatever the tab preloaded — no loads of its own.
struct CalorieCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<CalorieSettings>
    @ObservedObject var month: WidgetStateController<CalorieMonth>

    var body: some View {
        let theme = context.theme
        let totals = month.model.totals(on: context.today)
        let goal = settings.model.dailyGoalKcal
        WidgetCard(context: context, action: WidgetQuickAction("Add", symbolName: "plus") {
            context.host.haptic(.light)
            context.track("widget_card_action", ["action": "add"])
            context.openFullView()
        }) {
            HStack(spacing: 12) {
                CalorieRingView(consumed: totals.kcal, goal: goal, theme: theme, accent: context.accent, size: 56, lineWidth: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(CalorieFormat.kcal(totals.kcal)) / \(CalorieFormat.kcal(goal)) kcal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.label)
                    if let macros = CalorieFormat.macroLine(totals) {
                        Text(macros)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                            .lineLimit(1)
                    } else {
                        Text(totals.kcal == 0 ? "Nothing logged yet today" : "\(CalorieFormat.kcal(max(0, goal - totals.kcal))) left")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
        }
    }
}

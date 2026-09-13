import SwiftUI
import FavWidgetsCore

/// Card: "5 / 8 cups today", a row of drops, a thin progress bar, and a
/// "+ Cup" quick action.
struct WaterCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WaterLog>

    /// Drops beyond this many are summarised rather than drawn.
    private static let maxDrops = 12

    var body: some View {
        let theme = context.theme
        let model = state.model
        let today = context.today
        let cups = model.cups(on: today)
        let goal = max(1, model.goalCups)
        let reached = cups >= goal

        WidgetCard(context: context, action: quickAction) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetUI.summary(summaryText(cups: cups, goal: goal, reached: reached), theme: theme)
                dropRow(cups: cups, goal: goal, theme: theme)
                WidgetUI.progressBar(fraction: Double(cups) / Double(goal), color: context.accent, theme: theme)
            }
        }
        .task { await state.loadIfNeeded() }
    }

    private var quickAction: WidgetQuickAction {
        WidgetQuickAction("Cup", symbolName: "plus") {
            let today = context.today
            state.update { $0.add(1, on: today, calendar: context.calendar) }
            context.host.haptic(.light)
            context.track("widget_card_action", ["action": "add_cup"])
        }
    }

    private func summaryText(cups: Int, goal: Int, reached: Bool) -> String {
        guard reached else { return "\(cups) / \(goal) cups today" }
        let streak = state.model.streak(endingOn: context.today, calendar: context.calendar)
        return "Goal reached 🎉 · \(streak)-day streak"
    }

    @ViewBuilder
    private func dropRow(cups: Int, goal: Int, theme: WidgetTheme) -> some View {
        let shown = min(goal, Self.maxDrops)
        HStack(spacing: 3) {
            ForEach(0..<shown, id: \.self) { index in
                Image(systemName: index < cups ? "drop.fill" : "drop")
                    .font(.system(size: 12))
                    .foregroundStyle(index < cups ? context.accent : theme.secondaryLabel.opacity(0.5))
            }
            if goal > Self.maxDrops || cups > shown {
                Text(cups > shown ? "+\(cups - shown)" : "…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cups) of \(goal) cups")
    }
}

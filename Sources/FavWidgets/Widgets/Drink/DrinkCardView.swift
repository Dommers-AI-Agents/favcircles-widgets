import SwiftUI
import FavWidgetsCore

struct DrinkCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<DrinkSettings>

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction("Shake again", symbolName: "dice.fill") {
            context.track("widget_card_action", ["action": "shake"])
            context.host.haptic(.light)
            state.shake()
        }) {
            if let drink = state.model.currentPick {
                Text("Order a \(drink.name) \(drink.base.emoji)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                WidgetUI.summary(drink.blurb, theme: theme)
            } else {
                WidgetUI.summary("Tap Shake again for a drink to order", theme: theme)
            }
        }
        .task {
            await state.loadIfNeeded()
            if state.model.currentPickId == nil { state.shake() }
        }
    }
}

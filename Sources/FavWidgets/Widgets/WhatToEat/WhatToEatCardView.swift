import SwiftUI
import FavWidgetsCore

struct WhatToEatCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WhatToEatSettings>

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction("Spin", symbolName: "arrow.triangle.2.circlepath") {
            context.track("widget_card_action", ["action": "spin"])
            context.host.haptic(.light)
            state.spin()
        }) {
            if let cuisine = state.model.currentCuisine, let dish = state.model.currentDish {
                Text("Tonight: \(cuisine.name) \(cuisine.emoji)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                WidgetUI.summary("Try the \(dish.lowercasedFirst)", theme: theme)
            } else {
                WidgetUI.summary("Can't decide? Tap Spin", theme: theme)
            }
        }
        .task {
            await state.loadIfNeeded()
            if state.model.currentCuisineId == nil { state.spin() }
        }
    }
}

extension String {
    /// "Pad see ew" stays; "Chicken tikka masala" → "chicken tikka masala".
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

import SwiftUI
import FavWidgetsCore

struct FridgeMailCardView: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction("Add", symbolName: "plus") {
            context.track("widget_card_action", ["action": "add_drawing"])
            context.openFullView()
        }) {
            HStack(spacing: 10) {
                if let next = store.plan?.nextItem, let url = next.imageURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 42, height: 32)
                    .background(FridgeMailCanvasView.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(FridgeMailCanvasView.frame.opacity(0.5), lineWidth: 1))
                }
                WidgetUI.summary(FridgeMailCopy.cardSummary(store.plan, calendar: context.calendar), theme: theme)
            }
        }
        .task { await store.loadIfNeeded(context: context) }
    }
}

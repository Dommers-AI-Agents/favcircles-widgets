import SwiftUI
import FavWidgetsCore

/// The card: today's line if it has arrived, otherwise what to expect. Same
/// frame as every other card (icon, title, quick action); the body is the
/// quote itself when there is one.
struct QuotesCardView: View {
    let context: WidgetContext
    @ObservedObject var store: QuotesStore

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction(store.prefs.enabled ? "Open" : "Set up", symbolName: "quote.opening") {
            context.track("widget_card_action", ["action": store.prefs.enabled ? "open" : "setup"])
            context.openFullView()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                if let quote = store.today {
                    Text(quote.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.label)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let attribution = quote.attribution {
                        Text(attribution).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                } else if store.prefs.enabled {
                    WidgetUI.summary("Your quote arrives at \(QuoteCopy.friendly(store.prefs.time))", theme: theme)
                } else {
                    WidgetUI.summary("A good line to start the day · tap to choose your topics and time", theme: theme)
                }
            }
        }
        .task { await store.loadIfNeeded(context: context) }
    }
}

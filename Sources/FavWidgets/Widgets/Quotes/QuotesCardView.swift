import SwiftUI
import FavWidgetsCore

/// The card: today's line if it has arrived, otherwise what to expect.
struct QuotesCardView: View {
    let context: WidgetContext
    @ObservedObject var store: QuotesStore

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 8) {
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
                Text("Your quote arrives at \(QuoteCopy.friendly(store.prefs.time))")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            } else {
                Text("A good line to start the day")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                Text("Tap to choose your topics and time")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await store.loadIfNeeded(context: context) }
    }
}


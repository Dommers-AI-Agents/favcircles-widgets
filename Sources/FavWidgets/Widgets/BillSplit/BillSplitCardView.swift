import SwiftUI
import FavWidgetsCore

struct BillSplitCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<BillSplitSettings>

    var body: some View {
        let theme = context.theme
        let model = settings.model
        WidgetCard(context: context, action: WidgetQuickAction("Split", symbolName: "divide") {
            context.track("widget_card_action", ["action": "split"])
            context.openFullView()
        }) {
            VStack(alignment: .leading, spacing: 2) {
                WidgetUI.summary(BillSplitFormatting.summary(tipPercent: model.lastTipPercent, people: model.defaultPeople), theme: theme)
                if let place = model.lastPlace {
                    Text("Last: \(place.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .task { await settings.loadIfNeeded() }
    }
}

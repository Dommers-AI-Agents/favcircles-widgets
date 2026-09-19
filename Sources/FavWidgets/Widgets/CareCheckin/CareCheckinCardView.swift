import SwiftUI
import FavWidgetsCore

struct CareCheckinCardView: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore

    var body: some View {
        let theme = context.theme
        let plans = store.plans
        let hasOpen = !(plans?.openAsks.isEmpty ?? true) || !(plans?.invitations.isEmpty ?? true)
        WidgetCard(context: context, action: WidgetQuickAction(hasOpen ? "Answer" : "Open", symbolName: hasOpen ? "hand.thumbsup.fill" : "arrow.up.right") {
            context.track("widget_card_action", ["action": hasOpen ? "answer" : "open"])
            context.openFullView()
        }) {
            WidgetUI.summary(CareCopy.cardSummary(plans, calendar: context.calendar), theme: theme)
        }
        .task { await store.loadIfNeeded(context: context) }
    }
}

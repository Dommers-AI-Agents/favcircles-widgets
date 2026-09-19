import SwiftUI
import FavWidgetsCore

struct HeartbeatCardView: View {
    let context: WidgetContext
    @ObservedObject var month: WidgetStateController<HeartbeatMonth>
    @ObservedObject var previousMonth: WidgetStateController<HeartbeatMonth>

    private var latest: HeartReading? {
        [month.model.latest, previousMonth.model.latest].compactMap { $0 }.max { $0.at < $1.at }
    }

    var body: some View {
        WidgetCard(context: context, action: WidgetQuickAction("Measure", symbolName: "heart.fill") {
            context.track("widget_card_action", ["action": "measure"])
            context.openFullView()
        }) {
            WidgetUI.summary(HeartbeatCopy.cardSummary(latest: latest, calendar: context.calendar), theme: context.theme)
        }
        .task {
            await month.loadIfNeeded()
            await previousMonth.loadIfNeeded()
        }
    }
}

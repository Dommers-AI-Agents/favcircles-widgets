import SwiftUI
import FavWidgetsCore

/// Heartbeat: measure your pulse with a fingertip over the camera, or live
/// from a Bluetooth strap. Readings log into monthly shards.
public struct HeartbeatWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "heartbeat",
        title: "Heartbeat",
        subtitle: "Your pulse, from the camera or a strap",
        symbolName: "heart.fill",
        accentHex: "#F43F5E",
        category: .health,
        storage: .monthly
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(HeartbeatCardView(
            context: context,
            month: context.month(HeartbeatMonth.self, context.currentMonth),
            previousMonth: context.month(HeartbeatMonth.self, context.currentMonth.previous)
        ))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(HeartbeatFullView(
            context: context,
            settings: context.state(HeartbeatSettings.self),
            month: context.month(HeartbeatMonth.self, context.currentMonth),
            previousMonth: context.month(HeartbeatMonth.self, context.currentMonth.previous)
        ))
    }
}

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

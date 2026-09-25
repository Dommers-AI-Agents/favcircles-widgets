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
        storage: .monthly,
        shareBlurb: "Measure your heart rate directly from your phone camera."
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


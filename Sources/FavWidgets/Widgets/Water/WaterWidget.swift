import SwiftUI
import FavWidgetsCore

/// Daily water intake: one tap per cup, a goal, and a streak. Single
/// document for all time (`WaterLog`).
public struct WaterWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "water",
        title: "Water",
        subtitle: "Tap to log each glass",
        symbolName: "drop.fill",
        accentHex: "#4299E1",
        category: .health,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WaterCardView(context: context, state: context.state(WaterLog.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(WaterFullView(context: context, state: context.state(WaterLog.self)))
    }
}

/// Cup sizes offered in settings (ml).
enum WaterCupSizes {
    static let all = [200, 250, 300, 350, 500]
}

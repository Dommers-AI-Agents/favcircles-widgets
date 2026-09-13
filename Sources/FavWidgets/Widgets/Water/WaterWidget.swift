import SwiftUI
import FavWidgetsCore

// STUB — replaced by the real implementation.
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
        AnyView(WidgetCard(context: context) {
            WidgetUI.summary("Coming soon", theme: context.theme)
        })
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(Text("Water").padding())
    }
}

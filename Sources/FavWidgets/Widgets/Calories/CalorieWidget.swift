import SwiftUI
import FavWidgetsCore

// STUB — replaced by the real implementation.
public struct CalorieWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "calories",
        title: "Calories",
        subtitle: "Quick-add meals and macros",
        symbolName: "flame.fill",
        accentHex: "#FF8500",
        category: .health,
        storage: .monthly
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WidgetCard(context: context) {
            WidgetUI.summary("Coming soon", theme: context.theme)
        })
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(Text("Calories").padding())
    }
}

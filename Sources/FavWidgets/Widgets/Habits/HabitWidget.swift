import SwiftUI
import FavWidgetsCore

// STUB — replaced by the real implementation.
public struct HabitWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "habits",
        title: "Habits",
        subtitle: "Daily check-ins and streaks",
        symbolName: "checkmark.circle.fill",
        accentHex: "#38A169",
        category: .health,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WidgetCard(context: context) {
            WidgetUI.summary("Coming soon", theme: context.theme)
        })
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(Text("Habits").padding())
    }
}

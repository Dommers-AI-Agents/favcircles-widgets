import SwiftUI
import FavWidgetsCore

// STUB — replaced by the real implementation.
public struct WorkoutWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "workouts",
        title: "Workouts",
        subtitle: "Log sets, reps and PRs",
        symbolName: "dumbbell.fill",
        accentHex: "#3182CE",
        category: .fitness,
        storage: .monthly
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WidgetCard(context: context) {
            WidgetUI.summary("Coming soon", theme: context.theme)
        })
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(Text("Workouts").padding())
    }
}

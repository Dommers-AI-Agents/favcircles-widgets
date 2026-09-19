import SwiftUI
import FavWidgetsCore

/// One mini-app. The tab renders `makeCardView` in the scrolling list and
/// pushes `makeFullView` when the card is opened.
@MainActor
public protocol FavWidget {
    var descriptor: FavWidgetDescriptor { get }
    /// Compact card: a live summary plus at most one quick action. Must
    /// render from cached/empty state with no network.
    func makeCardView(context: WidgetContext) -> AnyView
    /// The full screen. Created on demand, released on pop.
    func makeFullView(context: WidgetContext) -> AnyView
    /// Pull-to-refresh on the tab. Default: reload every loaded document.
    func refresh(context: WidgetContext) async
}

public extension FavWidget {
    func refresh(context: WidgetContext) async {
        for controller in context.cache.all where controller.documentId.hasPrefix(descriptor.id) {
            await controller.reload()
        }
    }
}

/// Every widget the package ships. Adding one = adding its folder under
/// `Widgets/` and one line here.
@MainActor
public enum FavWidgetRegistry {
    public static let all: [any FavWidget] = [
        WaterWidget(),
        HabitWidget(),
        CalorieWidget(),
        WorkoutWidget(),
        BillSplitWidget(),
        PostcardWidget(),
        NextBarWidget(),
        StocksWidget(),
        FridgeMailWidget(),
        SleepSoundsWidget()
    ]

    public static var descriptors: [FavWidgetDescriptor] { all.map(\.descriptor) }

    public static func widget(id: String) -> (any FavWidget)? {
        all.first { $0.descriptor.id == id }
    }
}

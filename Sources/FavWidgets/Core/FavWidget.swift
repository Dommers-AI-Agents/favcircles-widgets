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
    /// What the Share button's card shows: the widget's latest thing worth
    /// sharing. Default nil = the generic card (WidgetShareCardContent.generic).
    func shareCard(context: WidgetContext) async -> WidgetShareCardContent?
}

public extension FavWidget {
    func shareCard(context: WidgetContext) async -> WidgetShareCardContent? { nil }

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
        WeatherWidget(),
        HabitWidget(),
        CalorieWidget(),
        WorkoutWidget(),
        RunWidget(),
        MotivationWidget(),
        BillSplitWidget(),
        PostcardWidget(),
        NextBarWidget(),
        EventsWidget(),
        DrinkWidget(),
        WhatToEatWidget(),
        StocksWidget(),
        FridgeMailWidget(),
        SleepSoundsWidget(),
        CareCheckinWidget(),
        QuotesWidget(),
        HeartbeatWidget(),
        MedsWidget(),
        SleepWidget(),
        ParkingWidget(),
        PackagesWidget(),
        NewContactsWidget()
    ]

    public static var descriptors: [FavWidgetDescriptor] { all.map(\.descriptor) }

    public static func widget(id: String) -> (any FavWidget)? {
        all.first { $0.descriptor.id == id }
    }
}

import SwiftUI
import FavWidgetsCore

/// Fridge Mail: kids' drawings and photos, printed and mailed to the
/// grandparents every week without anyone remembering to do it. The plan,
/// the queue, and the weekly run all live on the server; the widget is
/// the place to add a drawing, a grandparent, and cards.
public struct FridgeMailWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "fridgemail",
        title: "Fridge Mail",
        subtitle: "Kids' drawings, mailed to Grandma every week",
        symbolName: "paintpalette.fill",
        accentHex: "#D97706",
        category: .social,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(FridgeMailCardView(context: context, store: FridgeMailStore.shared(context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(FridgeMailFullView(context: context, store: FridgeMailStore.shared(context)))
    }

    /// Nothing is cached in widget documents, so pull-to-refresh has to
    /// ask the server again.
    public func refresh(context: WidgetContext) async {
        await FridgeMailStore.shared(context).load(context: context)
    }
}

import SwiftUI
import FavWidgetsCore

/// "Make Me a Drink": a cocktail to order right now, picked by base spirit,
/// and the recipe for any classic.
public struct DrinkWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "drink",
        title: "Make Me a Drink",
        subtitle: "A cocktail to order, and how to make it",
        symbolName: "wineglass",
        accentHex: "#D53F8C",
        category: .social,
        storage: .single,
        shareBlurb: "A cocktail to order tonight, and how to make any classic."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(DrinkCardView(context: context, state: context.state(DrinkSettings.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(DrinkFullView(context: context, state: context.state(DrinkSettings.self)))
    }
}

extension WidgetStateController where Model == DrinkSettings {
    /// Picks a fresh drink for the saved base filter and stores it.
    @discardableResult
    func shake() -> Cocktail? {
        guard let drink = DrinkPicker.random(base: model.baseFilter, excluding: model.recentIds) else { return nil }
        update { $0.notePick(drink) }
        return drink
    }
}

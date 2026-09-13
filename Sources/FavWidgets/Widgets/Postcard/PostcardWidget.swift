import SwiftUI
import FavWidgetsCore

// STUB — replaced by the real implementation.
public struct PostcardWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "postcard",
        title: "Postcard",
        subtitle: "Send a postcard from your trip",
        symbolName: "envelope.open.fill",
        accentHex: "#E53E3E",
        category: .social,
        storage: .monthly
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WidgetCard(context: context) {
            WidgetUI.summary("Coming soon", theme: context.theme)
        })
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(Text("Postcard").padding())
    }
}

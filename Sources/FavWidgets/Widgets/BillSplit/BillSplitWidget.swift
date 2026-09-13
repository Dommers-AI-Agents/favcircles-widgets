import SwiftUI
import FavWidgetsCore

// STUB — replaced by the real implementation.
public struct BillSplitWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "billsplit",
        title: "Bill Split",
        subtitle: "Split the check, add the tip",
        symbolName: "receipt.fill",
        accentHex: "#4FD1C5",
        category: .money,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WidgetCard(context: context) {
            WidgetUI.summary("Coming soon", theme: context.theme)
        })
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(Text("Bill Split").padding())
    }
}

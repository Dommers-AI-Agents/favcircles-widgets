import SwiftUI
import FavWidgetsCore

/// Split the check: a live calculator whose defaults (tip %, people,
/// toggles, last place) persist; amounts are per bill and never stored.
public struct BillSplitWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "billsplit",
        title: "Bill Split",
        subtitle: "Split the check, add the tip",
        symbolName: "receipt.fill",
        accentHex: "#4FD1C5",
        category: .money,
        storage: .single,
        shareBlurb: "Split the check and the tip with friends in seconds."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(BillSplitCardView(context: context, settings: context.state(BillSplitSettings.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(BillSplitFullView(context: context, settings: context.state(BillSplitSettings.self)))
    }
}

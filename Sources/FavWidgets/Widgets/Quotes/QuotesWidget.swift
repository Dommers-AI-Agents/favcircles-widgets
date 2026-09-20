import SwiftUI
import FavWidgetsCore

/// Good lines at the times you choose — one a day or several — about the
/// things you asked for; pushed to the phone, and to your inbox if you want.
///
/// The settings live on the server rather than in a widget document, because
/// the scheduler has to read them to know who to send to and when.
public struct QuotesWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "quotes",
        title: "Quotes",
        subtitle: "Good lines at the times you pick",
        symbolName: "quote.opening",
        accentHex: "#7C6BD6",
        category: .social,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(QuotesCardView(context: context, store: QuotesStore.shared(context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(QuotesFullView(context: context, store: QuotesStore.shared(context)))
    }

    public func refresh(context: WidgetContext) async {
        await QuotesStore.shared(context).load(context: context)
    }
}

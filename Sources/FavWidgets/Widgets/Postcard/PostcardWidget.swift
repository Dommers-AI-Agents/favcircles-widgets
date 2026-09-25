import SwiftUI
import FavWidgetsCore

/// Send a digital postcard (photo + template + caption) to a connection.
/// Drafts live in the settings document; every sent card is a permanent
/// record in that month's shard.
public struct PostcardWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "postcard",
        title: "Postcard",
        subtitle: "Send a postcard from your trip",
        symbolName: "envelope.open.fill",
        accentHex: "#E53E3E",
        category: .social,
        storage: .monthly,
        shareBlurb: "Send a real postcard from a trip photo, printed and mailed for you."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        let month = context.currentMonth
        return AnyView(PostcardCardView(
            context: context,
            currentMonth: context.month(PostcardMonth.self, month),
            previousMonth: context.month(PostcardMonth.self, month.previous)
        ))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        let month = context.currentMonth
        return AnyView(PostcardFullView(
            context: context,
            settings: context.state(PostcardSettings.self),
            currentMonth: context.month(PostcardMonth.self, month),
            previousMonth: context.month(PostcardMonth.self, month.previous)
        ))
    }
}

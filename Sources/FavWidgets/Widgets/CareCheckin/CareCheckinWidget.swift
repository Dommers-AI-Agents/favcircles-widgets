import SwiftUI
import FavWidgetsCore

/// "How Are You?": an adult child sets up a few times a day when a parent
/// gets a short question as a push, answered with one tap from the Lock
/// Screen. Both sides use this one widget: the child manages questions
/// and sees answers (and silence); the parent accepts and answers.
public struct CareCheckinWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "howareyou",
        title: "How Are You?",
        subtitle: "Check on Mom or Dad, a few times a day",
        symbolName: "heart.text.square.fill",
        accentHex: "#E0567F",
        category: .social,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(CareCheckinCardView(context: context, store: CareStore.shared(context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(CareCheckinFullView(context: context, store: CareStore.shared(context)))
    }

    public func refresh(context: WidgetContext) async {
        await CareStore.shared(context).load(context: context)
    }
}


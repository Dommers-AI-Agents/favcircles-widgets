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

struct CareCheckinCardView: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore

    var body: some View {
        let theme = context.theme
        let plans = store.plans
        let hasOpen = !(plans?.openAsks.isEmpty ?? true) || !(plans?.invitations.isEmpty ?? true)
        WidgetCard(context: context, action: WidgetQuickAction(hasOpen ? "Answer" : "Open", symbolName: hasOpen ? "hand.thumbsup.fill" : "arrow.up.right") {
            context.track("widget_card_action", ["action": hasOpen ? "answer" : "open"])
            context.openFullView()
        }) {
            WidgetUI.summary(CareCopy.cardSummary(plans, calendar: context.calendar), theme: theme)
        }
        .task { await store.loadIfNeeded(context: context) }
    }
}

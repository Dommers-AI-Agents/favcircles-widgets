import SwiftUI
import FavWidgetsCore

struct PostcardCardView: View {
    let context: WidgetContext
    @ObservedObject var currentMonth: WidgetStateController<PostcardMonth>
    @ObservedObject var previousMonth: WidgetStateController<PostcardMonth>

    private var newest: PostcardRecord? {
        (currentMonth.model.sent + previousMonth.model.sent).max { $0.sentAt < $1.sentAt }
    }

    var body: some View {
        WidgetCard(context: context, action: WidgetQuickAction("New", symbolName: "plus") {
            context.track("widget_card_action", ["action": "new"])
            context.openFullView()
        }) {
            WidgetUI.summary(newest.map { PostcardCopy.summary(for: $0) } ?? context.descriptor.subtitle, theme: context.theme)
        }
        .task {
            await currentMonth.loadIfNeeded()
            await previousMonth.loadIfNeeded()
        }
    }
}

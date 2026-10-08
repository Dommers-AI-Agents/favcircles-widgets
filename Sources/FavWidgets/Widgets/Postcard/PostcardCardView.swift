import SwiftUI
import FavWidgetsCore

struct PostcardCardView: View {
    let context: WidgetContext
    @ObservedObject var currentMonth: WidgetStateController<PostcardMonth>
    @ObservedObject var previousMonth: WidgetStateController<PostcardMonth>

    private var newest: PostcardRecord? {
        (currentMonth.model.sent + previousMonth.model.sent).max { $0.sentAt < $1.sentAt }
    }

    /// "$1.99 · Today only" while a printed-card special runs
    @State private var specialBadge: String?

    var body: some View {
        WidgetCard(context: context, action: WidgetQuickAction("New", symbolName: "plus") {
            context.track("widget_card_action", ["action": "new"])
            context.openFullView()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                if let specialBadge {
                    Label(specialBadge, systemImage: "tag.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(context.accent))
                }
                WidgetUI.summary(newest.map { PostcardCopy.summary(for: $0) } ?? context.descriptor.subtitle, theme: context.theme)
            }
        }
        .task {
            await currentMonth.loadIfNeeded()
            await previousMonth.loadIfNeeded()
        }
        .task {
            guard let config = try? await PostcardMail.config(context: context), config.isUsable else { return }
            specialBadge = PostcardPriceCopy.badge(priceCents: config.priceCents,
                                                   regularPriceCents: config.regularPriceCents,
                                                   label: config.special?.label)
        }
    }
}

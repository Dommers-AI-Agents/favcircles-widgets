import SwiftUI
import FavWidgetsCore

struct NextBarCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<NextBarSettings>
    @ObservedObject var pool: NextBarPool

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: quickAction) {
            if let pick = state.model.currentPick, pick.day == context.today {
                Text(pick.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                WidgetUI.summary("\(NextBarFormat.distance(pick.distanceMeters)) away · \(NextBarFormat.attribution(pick.source, savedBy: pick.savedByName))", theme: theme)
            } else {
                switch pool.status {
                case .loading:
                    WidgetUI.summary("Finding bars near you…", theme: theme)
                case .failed(let message):
                    WidgetUI.summary(message, theme: theme)
                default:
                    WidgetUI.summary(pool.locationDenied && pool.status == .loaded
                                     ? "Turn on location to get a nearby pick"
                                     : "Tap Pick for tonight's bar", theme: theme)
                }
            }
        }
        .task {
            await state.loadIfNeeded()
            await pool.loadIfNeeded()
            autoPickIfStale()
        }
    }

    private var quickAction: WidgetQuickAction {
        let hasPick = state.model.currentPick?.day == context.today
        return WidgetQuickAction(hasPick ? "Shuffle" : "Pick", symbolName: hasPick ? "shuffle" : "sparkles") {
            context.track("widget_card_action", ["action": hasPick ? "shuffle" : "pick"])
            context.host.haptic(.light)
            if pool.status != .loaded {
                Task { await pool.reload(); _ = pool.roll(into: state, today: context.today) }
            } else if pool.roll(into: state, today: context.today) == nil {
                context.openFullView()   // nothing in range: the full view explains and offers the distance slider
            }
        }
    }

    /// A pick from a previous day is stale; make a fresh one silently.
    private func autoPickIfStale() {
        guard pool.status == .loaded, state.hasLoaded else { return }
        if let pick = state.model.currentPick, pick.day == context.today { return }
        _ = pool.roll(into: state, today: context.today)
    }
}

import SwiftUI
import FavWidgetsCore

/// Card: the coach (small, shouting until today is done) and this hour's
/// line, with a "Did it" quick action.
struct MotivationCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<MotivationLog>

    var body: some View {
        let theme = context.theme
        let model = state.model
        let count = model.doneCount(on: context.today)

        WidgetCard(context: context, action: quickAction(again: count > 0)) {
            HStack(alignment: .center, spacing: 10) {
                // He never settles: done once just means do it again
                CoachView(shouting: true, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.currentLine())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.label)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    let streak = model.streak(endingOn: context.today, calendar: context.calendar)
                    if count > 0 || streak > 0 {
                        Text([count > 0 ? "💪 \(count) today" : nil, streak > 0 ? "🔥 \(streak)-day streak" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
        }
        .task { await state.loadIfNeeded() }
    }

    private func quickAction(again: Bool) -> WidgetQuickAction {
        WidgetQuickAction(again ? "Again" : "Did it", symbolName: "checkmark") {
            let today = context.today
            state.update { $0.logDidIt(on: today) }
            context.host.haptic(.success)
            context.track("widget_card_action", ["action": "motivation_did_it"])
            let log = state.model
            let quiet = context.host.quietHours
            Task { await MotivationReminderScheduler.sync(log, quietHours: quiet) }
        }
    }
}

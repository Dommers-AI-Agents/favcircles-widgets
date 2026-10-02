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
        let done = model.isDone(context.today)

        WidgetCard(context: context, action: done ? nil : quickAction) {
            HStack(alignment: .center, spacing: 10) {
                CoachView(shouting: !done, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(done ? "Done today. Coach is (almost) proud." : model.currentLine())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.label)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    let streak = model.streak(endingOn: context.today, calendar: context.calendar)
                    if streak > 0 {
                        Text("🔥 \(streak)-day streak")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
        }
        .task { await state.loadIfNeeded() }
    }

    private var quickAction: WidgetQuickAction {
        WidgetQuickAction("Did it", symbolName: "checkmark") {
            let today = context.today
            state.update { $0.setDone(true, on: today) }
            context.host.haptic(.success)
            context.track("widget_card_action", ["action": "motivation_did_it"])
            let log = state.model
            let quiet = context.host.quietHours
            Task { await MotivationReminderScheduler.sync(log, quietHours: quiet) }
        }
    }
}

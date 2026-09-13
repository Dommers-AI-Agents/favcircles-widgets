import SwiftUI
import FavWidgetsCore

/// Card: an in-progress workout with a live elapsed clock and "Resume",
/// otherwise the last session + this month's PR count and "Start".
struct WorkoutCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @ObservedObject var currentMonth: WidgetStateController<WorkoutMonth>
    @ObservedObject var previousMonth: WidgetStateController<WorkoutMonth>

    var body: some View {
        let theme = context.theme
        if let session = settings.model.activeSession {
            WidgetCard(context: context, action: WidgetQuickAction("Resume", symbolName: "play.fill", handler: { open("resume") })) {
                TimelineView(.periodic(from: session.startedAt, by: 1)) { timeline in
                    let sets = WorkoutSessionLogic.completedSetCount(session)
                    let elapsed = WorkoutFormat.duration(timeline.date.timeIntervalSince(session.startedAt))
                    WidgetUI.summary("Workout in progress · \(sets) \(sets == 1 ? "set" : "sets") · \(elapsed)", theme: theme)
                }
            }
        } else {
            WidgetCard(context: context, action: WidgetQuickAction("Start", symbolName: "play.fill", handler: { open("start") })) {
                WidgetUI.summary(idleSummary, theme: theme)
            }
        }
    }

    private var idleSummary: String {
        guard let last = WorkoutSessionLogic.lastSession(in: [currentMonth.model, previousMonth.model]) else {
            return "No workouts yet"
        }
        let prs = WorkoutSessionLogic.recordCount(in: settings.model.prsByExercise, month: context.currentMonth, calendar: context.calendar)
        return "Last: \(last.name) · \(WorkoutFormat.relativeDay(last.startedAt, calendar: context.calendar)) · \(prs) \(prs == 1 ? "PR" : "PRs") this month"
    }

    private func open(_ action: String) {
        context.host.haptic(.light)
        context.track("widget_card_action", ["action": action])
        context.openFullView()
    }
}

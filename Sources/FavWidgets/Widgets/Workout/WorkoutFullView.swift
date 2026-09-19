import SwiftUI
import FavWidgetsCore

/// Full screen: the active session when there is one (unless the person
/// backed out of it to the widget's home page); otherwise Start (routines),
/// Inner Circle workouts, History (months on demand), PRs and settings.
struct WorkoutFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @State private var summary: WorkoutSummary?
    /// The live workout is still running, but the person tapped Back to
    /// look at the home page. Resume brings it back.
    @State private var showHomeWhileActive = false

    private var showsSession: Bool { settings.model.activeSession != nil && !showHomeWhileActive }

    var body: some View {
        Group {
            if showsSession {
                ActiveSessionView(context: context, settings: settings, onFinished: { summary = $0 }, onBack: {
                    showHomeWhileActive = true
                })
            } else {
                WorkoutHomeView(context: context, settings: settings, onResume: { showHomeWhileActive = false })
            }
        }
        .task {
            await settings.loadIfNeeded()
            await context.month(WorkoutMonth.self, context.currentMonth).loadIfNeeded()
            await context.month(WorkoutMonth.self, context.currentMonth.previous).loadIfNeeded()
        }
        .onChange(of: settings.model.activeSession == nil) { ended in
            if ended { showHomeWhileActive = false }
        }
        .sheet(item: $summary) { summary in
            WorkoutSummaryView(context: context, settings: settings, summary: summary)
        }
        .background(context.theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("Workouts")
    }
}

// MARK: - Summary sheet


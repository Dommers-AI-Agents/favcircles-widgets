import SwiftUI
import FavWidgetsCore

/// Keeps the history the person's Inner Circle can browse in step with this
/// phone: sent when the setting changes, when a workout finishes, and once
/// per launch when the widget opens (edits made since).
@MainActor
enum WorkoutHistorySync {
    private final class Once { var done = false }

    static func sync(context: WidgetContext, settings: WorkoutSettings) async {
        var summaries: [WorkoutShareSummary] = []
        if settings.shareHistoryWithInnerCircle {
            var month = context.currentMonth
            var sessions: [WorkoutSession] = []
            for _ in 0..<WorkoutHistoryShare.months {
                let controller = context.month(WorkoutMonth.self, month)
                await controller.loadIfNeeded()
                sessions += controller.model.sessions
                month = month.previous
            }
            summaries = WorkoutHistoryShare.summaries(sessions, settings: settings)
        }
        do {
            try await WorkoutFeedAPI.syncHistory(context: context, enabled: settings.shareHistoryWithInnerCircle, workouts: summaries)
        } catch {
            context.track("workout_history_sync_failed")
        }
    }

    /// The once-per-launch catch-up, only for people who have it on.
    static func syncOnOpen(context: WidgetContext, settings: WorkoutSettings) async {
        guard settings.shareHistoryWithInnerCircle else { return }
        let once = context.transient("workouts.historySynced") { Once() }
        guard !once.done else { return }
        once.done = true
        await sync(context: context, settings: settings)
    }
}

/// Someone's workout history, opened from one of their shared workouts.
/// Only their Inner Circle gets here (the server checks); tap a workout to
/// see it in full and copy it.
struct WorkoutAuthorHistoryView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let userId: String
    let userName: String

    @State private var history: WorkoutFeedAPI.History?
    @State private var failed = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        Group {
            if let history {
                if history.workouts.isEmpty {
                    message("No workouts yet", detail: "\(userName)'s finished workouts will show up here.")
                } else {
                    List {
                        ForEach(groups(history), id: \.title) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    NavigationLink {
                                        WorkoutPostView(context: context, settings: settings, postId: entry.postId,
                                                        initialPost: history.post(entry), embedded: true)
                                    } label: { row(entry.summary) }
                                    .listRowBackground(theme.secondaryBackground)
                                }
                            } header: {
                                Text(group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else if failed {
                message("This history isn't available", detail: "\(userName) may have stopped sharing it.")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("\(userName)'s workouts")
        .task {
            guard history == nil else { return }
            do { history = try await WorkoutFeedAPI.history(context: context, userId: userId) } catch { failed = true }
            context.track("workout_history_viewed")
        }
    }

    private struct MonthGroup { let title: String; let entries: [WorkoutFeedAPI.History.Entry] }

    /// By month, newest first (the server already sends them in that order).
    private func groups(_ history: WorkoutFeedAPI.History) -> [MonthGroup] {
        var out: [MonthGroup] = []
        for entry in history.workouts {
            let title = WorkoutFormat.monthTitle(MonthKey(entry.summary.startedAt, calendar: context.calendar), calendar: context.calendar)
            if out.last?.title == title {
                out[out.count - 1] = MonthGroup(title: title, entries: out[out.count - 1].entries + [entry])
            } else {
                out.append(MonthGroup(title: title, entries: [entry]))
            }
        }
        return out
    }

    private func row(_ summary: WorkoutShareSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(summary.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                if summary.prCount > 0 { Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundStyle(theme.warning) }
                Spacer()
                Text(WorkoutFormat.shortDate(summary.startedAt, calendar: context.calendar))
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Text(detail(summary)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    /// "52 min · 14 sets · 20 min cardio"
    private func detail(_ summary: WorkoutShareSummary) -> String {
        var parts = [WorkoutFormat.shortDuration(TimeInterval(summary.durationSeconds))]
        if summary.completedSets > 0 { parts.append("\(summary.completedSets) sets") }
        if summary.cardioMinutes > 0 { parts.append("\(summary.cardioMinutes) min cardio") }
        if summary.prCount > 0 { parts.append("\(summary.prCount) PR\(summary.prCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell").font(.system(size: 32)).foregroundStyle(theme.secondaryLabel)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
            Text(detail).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

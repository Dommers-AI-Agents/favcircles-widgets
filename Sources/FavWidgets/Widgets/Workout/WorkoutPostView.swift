import SwiftUI
import FavWidgetsCore

/// Someone's shared workout, opened from the activity feed (or the Inner
/// Circle list): what they did, and a button that makes it the viewer's own
/// routine — then starts it.
struct WorkoutPostView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let postId: String
    /// Already in hand (the Inner Circle list has it); skips the fetch
    var initialPost: WorkoutFeedAPI.Post?
    /// What the feed row already knows, shown while the workout loads
    var previewTitle: String?
    var previewDetail: String?
    /// Opened from outside the widget (the activity feed): after Start, the
    /// host opens the Workouts page so the live workout is on screen
    var onStarted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var post: WorkoutFeedAPI.Post?
    @State private var failed = false
    /// The routine this post became on this phone, once copied
    @State private var copied: Routine?
    @State private var notice: String?

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        NavigationStack {
            Group {
                if let post {
                    content(post)
                } else if failed {
                    VStack(spacing: 10) {
                        Image(systemName: "dumbbell").font(.system(size: 32)).foregroundStyle(theme.secondaryLabel)
                        Text("This workout isn't available.").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                        Text("It may have been shared with a smaller group.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let previewTitle {
                    // The row's own words straight away, the details a moment later
                    VStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 34)).foregroundStyle(context.accent)
                        Text(previewTitle).font(.system(size: 22, weight: .bold)).foregroundStyle(theme.label)
                            .multilineTextAlignment(.center)
                        if let previewDetail, !previewDetail.isEmpty {
                            Text(previewDetail).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        }
                        ProgressView().padding(.top, 6)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task { await load() }
    }

    private func load() async {
        if post == nil, let initialPost { post = initialPost }
        if post == nil {
            do { post = try await WorkoutFeedAPI.post(context: context, id: postId) } catch { failed = true }
        }
        await settings.loadIfNeeded()
        if let post { copied = WorkoutCopyLogic.existingCopy(of: post.summary, in: settings.model) }
        context.track("workout_post_viewed")
    }

    @ViewBuilder
    private func content(_ post: WorkoutFeedAPI.Post) -> some View {
        let summary = post.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    avatar(post)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(post.userName)'s workout").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                        Text(summary.name).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.label)
                        Text(WorkoutFormat.shortDate(summary.startedAt, calendar: context.calendar))
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                }
                HStack(spacing: 12) {
                    stat("Duration", WorkoutFormat.shortDuration(TimeInterval(summary.durationSeconds)))
                    if !summary.exercises.isEmpty {
                        stat("Exercises", "\(summary.exercises.count)")
                        stat("Sets", "\(summary.completedSets)")
                    }
                    if summary.prCount > 0 { stat("PRs", "\(summary.prCount)") }
                }
                if !summary.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        WidgetUI.header("Exercises", theme: theme)
                        ForEach(Array(summary.exercises.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.name).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label)
                                    Text("\(line.sets) set\(line.sets == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                                }
                                Spacer()
                                Text(line.bestSet).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(theme.label)
                                if line.isPR { Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(theme.warning) }
                            }
                        }
                    }
                }
                if !summary.cardio.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetUI.header("Cardio", theme: theme)
                        ForEach(Array(summary.cardio.enumerated()), id: \.offset) { _, line in
                            HStack {
                                Text(line.name).font(.system(size: 15)).foregroundStyle(theme.label)
                                Spacer()
                                Text(line.detail).font(.system(size: 14, design: .rounded)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                    }
                }
                if !summary.exercises.isEmpty { copyBlock(post) }
            }
            .padding(20)
        }
    }

    /// Copy → Start. Copying adds a routine (and any exercises they don't
    /// have yet); starting opens it as a live workout with their own last
    /// numbers filled in.
    @ViewBuilder
    private func copyBlock(_ post: WorkoutFeedAPI.Post) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let copied {
                WidgetUI.primaryButton(settings.model.activeSession == nil ? "Start this workout" : "Finish your current workout first",
                                       color: context.accent) { start(copied) }
                    .disabled(settings.model.activeSession != nil)
                    .opacity(settings.model.activeSession == nil ? 1 : 0.5)
                Text(notice ?? "It's in your routines as \u{201C}\(copied.name)\u{201D}.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                WidgetUI.primaryButton("Copy this routine", color: context.accent) { copy(post) }
                Text("Saves these exercises as a routine you can start any time. Your own weights fill in as you go.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func copy(_ post: WorkoutFeedAPI.Post) {
        let name = WorkoutCopyLogic.routineName(post.summary.name, author: post.userName, existing: settings.model.routines)
        let result = WorkoutCopyLogic.copy(post.summary, named: name, into: settings.model)
        guard !result.routine.items.isEmpty else { return }
        settings.update { model in
            model.customExercises.append(contentsOf: result.newExercises)
            model.routines.append(result.routine)
        }
        copied = result.routine
        notice = "Saved to your routines as \u{201C}\(result.routine.name)\u{201D}."
        context.host.haptic(.success)
        context.track("workout_post_copied", ["exercises": String(result.routine.items.count)])
    }

    private func start(_ routine: Routine) {
        guard settings.model.activeSession == nil else { return }
        let session = WorkoutSessionLogic.session(from: routine, history: context.recentWorkouts())
        settings.update { $0.activeSession = session }
        context.host.haptic(.light)
        context.track("workout_started", ["routine": "copied"])
        dismiss()
        onStarted?()
    }

    private func avatar(_ post: WorkoutFeedAPI.Post) -> some View {
        AsyncImage(url: post.avatarUrl.flatMap(URL.init(string:))) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() } else {
                ZStack {
                    Circle().fill(context.accent.opacity(0.15))
                    Text(String(post.userName.prefix(1)).uppercased()).font(.system(size: 18, weight: .bold)).foregroundStyle(context.accent)
                }
            }
        }
        .frame(width: 48, height: 48).clipShape(Circle())
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(theme.label).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }
}

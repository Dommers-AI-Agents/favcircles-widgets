import SwiftUI
import FavWidgetsCore

struct WorkoutSummaryView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss
    @State private var posting = false
    @State private var posted = false
    @ObservedObject private var audience: WorkoutAudienceStore
    /// nil = not answered yet, true = the routine was updated, false = left alone.
    @State private var routineAnswer: Bool?

    init(context: WidgetContext, settings: WidgetStateController<WorkoutSettings>, summary: WorkoutSummary) {
        self.context = context
        self.settings = settings
        self.summary = summary
        self.audience = WorkoutAudienceStore.shared(context)
    }

    private var theme: WidgetTheme { context.theme }
    private var share: WorkoutShareSummary { summary.share }

    /// The list the post goes to, if it still exists; a deleted or emptied
    /// list falls back to "anyone on my lists" rather than to nobody.
    private var chosenList: WorkoutFeedAPI.AudienceList? {
        guard let id = settings.model.shareListId else { return nil }
        return audience.lists.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout complete").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                        Text(summary.name).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.label)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(theme.success)
                }
                HStack(spacing: 12) {
                    stat("Duration", WorkoutFormat.duration(summary.duration))
                    if !share.exercises.isEmpty {
                        stat("Exercises", "\(share.exercises.count)")
                        stat("Sets", "\(summary.completedSets)")
                    }
                    if share.cardioMinutes > 0 { stat("Cardio", "\(share.cardioMinutes) min") }
                }
                if !share.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetUI.header("Best sets", theme: theme)
                        ForEach(Array(share.exercises.enumerated()), id: \.offset) { _, line in
                            HStack {
                                Text(line.name).font(.system(size: 15)).foregroundStyle(theme.label)
                                Spacer()
                                Text(line.bestSet).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(theme.label)
                                if line.isPR { Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(theme.warning) }
                            }
                        }
                    }
                }
                if !share.cardio.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetUI.header("Cardio", theme: theme)
                        ForEach(Array(share.cardio.enumerated()), id: \.offset) { _, line in
                            HStack {
                                Text(line.name).font(.system(size: 15)).foregroundStyle(theme.label)
                                Spacer()
                                Text(line.detail).font(.system(size: 14, design: .rounded)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                    }
                }
                if let update = summary.routineUpdate { routineCard(update) }
                if !summary.newRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetUI.header("New PRs", theme: theme)
                        ForEach(summary.newRecords, id: \.id) { item in
                            Label("\(item.exercise) \(WorkoutFormat.set(item.record.weight, item.record.reps))", systemImage: "trophy.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.label)
                        }
                    }
                }
                Toggle(isOn: Binding(get: { settings.model.shareWithInnerCircle }, set: { on in settings.update { $0.shareWithInnerCircle = on } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post to my Inner Circle").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label)
                        Text(posted ? "Posted." : "They see it in their Workouts widget.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
                if settings.model.shareWithInnerCircle, !posted, !audience.lists.isEmpty {
                    audiencePicker
                }
                HStack(spacing: 10) {
                    Button {
                        shareOut()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    WidgetUI.primaryButton(posting ? "Posting…" : "Done", color: context.accent) { finish() }
                        .disabled(posting)
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .task { await audience.loadIfStale(context: context) }
    }

    /// "You did it differently — keep the change?" Asked once, right after
    /// the workout, because that is the only moment the person still knows
    /// whether the change was the plan or a bad day.
    @ViewBuilder
    private func routineCard(_ update: RoutineUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: routineAnswer == true ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(routineAnswer == true ? theme.success : context.accent)
                Text(routineAnswer == true ? "\(update.routine.name) updated" : "Update \(update.routine.name)?")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
            }
            if routineAnswer == nil {
                Text(update.isNew
                     ? "This workout came from a starter routine. Saving keeps it as your own, with today's numbers."
                     : "Today didn't match the routine. Save today's numbers so next time starts here.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(update.changes.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 13, design: .rounded)).foregroundStyle(theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if routineAnswer == nil {
                HStack(spacing: 10) {
                    Button { acceptRoutine(update) } label: {
                        Text(update.isNew ? "Save as my routine" : "Update routine")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent))
                    }
                    .buttonStyle(.plain)
                    Button {
                        routineAnswer = false
                        context.track("workout_routine_update_declined")
                    } label: {
                        Text("Leave it")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.tertiaryBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private func acceptRoutine(_ update: RoutineUpdate) {
        settings.update { $0.routines = WorkoutSessionLogic.applying(update, to: $0.routines) }
        routineAnswer = true
        context.host.haptic(.success)
        context.track("workout_routine_updated", ["new": update.isNew ? "1" : "0"])
    }

    /// Which list. One entry per named list with its size, plus "anyone on my
    /// lists", which is what a post with no list has always meant.
    private var audiencePicker: some View {
        Menu {
            Button {
                settings.update { $0.shareListId = nil }
            } label: {
                Label("Anyone on my lists", systemImage: settings.model.shareListId == nil ? "checkmark" : "")
            }
            ForEach(audience.lists) { list in
                Button {
                    settings.update { $0.shareListId = list.id }
                } label: {
                    Label("\(list.name) · \(list.count == 1 ? "1 person" : "\(list.count) people")",
                          systemImage: settings.model.shareListId == list.id ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("To:").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                Text(chosenList?.name ?? "Anyone on my lists").font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private func shareOut() {
        var items: [WidgetShareItem] = [.text(share.shareText(calendar: context.calendar))]
        if let jpeg = WorkoutShareCard.jpeg(summary: share, accent: context.accent) { items.append(.imageJPEG(jpeg)) }
        context.track("workout_shared")
        context.host.share(items)
    }

    private func finish() {
        guard settings.model.shareWithInnerCircle, !posted else { dismiss(); return }
        posting = true
        Task {
            defer { posting = false }
            do {
                try await WorkoutFeedAPI.share(context: context, summary: share, audienceListId: chosenList?.id)
                posted = true
                context.track("workout_posted_inner_circle")
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't post to your Inner Circle", message: error.localizedDescription))
            }
        }
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

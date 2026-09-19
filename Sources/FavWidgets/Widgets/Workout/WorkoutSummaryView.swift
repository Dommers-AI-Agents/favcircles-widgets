import SwiftUI
import FavWidgetsCore

struct WorkoutSummaryView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss
    @State private var posting = false
    @State private var posted = false

    private var theme: WidgetTheme { context.theme }
    private var share: WorkoutShareSummary { summary.share }

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
                        Text(posted ? "Posted." : "The people on your Inner Circle list see it in their Workouts widget.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
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
                try await WorkoutFeedAPI.share(context: context, summary: share)
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

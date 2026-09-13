import SwiftUI
import FavWidgetsCore

/// One month of history rows; loads its shard on demand.
struct WorkoutMonthSection: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let monthKey: MonthKey
    @ObservedObject var controller: WidgetStateController<WorkoutMonth>
    let onSelect: (WorkoutSession) -> Void

    private var theme: WidgetTheme { context.theme }
    private var sessions: [WorkoutSession] { controller.model.sessions.sorted { $0.startedAt > $1.startedAt } }

    var body: some View {
        Group {
            HStack {
                Text(WorkoutFormat.monthTitle(monthKey, calendar: context.calendar))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                Spacer()
                if !controller.hasLoaded {
                    ProgressView().controlSize(.small)
                } else if sessions.isEmpty {
                    Text("No workouts").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .padding(.top, 4)
            .listRowSeparator(.hidden)
            ForEach(sessions) { session in
                Button { onSelect(session) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            Text(WorkoutFormat.shortDate(session.startedAt, calendar: context.calendar))
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(WorkoutFormat.shortDuration(WorkoutSessionLogic.duration(of: session))) · \(WorkoutSessionLogic.completedSetCount(session)) sets")
                                .font(.system(size: 13)).foregroundStyle(theme.label)
                            Text(WorkoutFormat.volume(session.totalVolume, unit: settings.model.unit))
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
        }
        .listRowBackground(Color.clear)
        .task { await controller.loadIfNeeded() }
    }
}

/// A finished session, exercise by exercise.
struct WorkoutSessionDetailView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                    Text("\(WorkoutFormat.shortDate(session.startedAt, calendar: context.calendar)) · \(WorkoutFormat.duration(WorkoutSessionLogic.duration(of: session))) · \(WorkoutFormat.volume(session.totalVolume, unit: settings.model.unit))")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Button("Done") { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.primary)
            }
            .padding(20)
            List {
                ForEach(WorkoutSessionLogic.orderedExerciseIds(in: session), id: \.self) { exerciseId in
                    let sets = session.sets.filter { $0.exerciseId == exerciseId }
                    Section {
                        ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text(set.isWarmup ? "W" : "\(index + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(set.isWarmup ? theme.warning : theme.secondaryLabel)
                                    .frame(width: 24)
                                Text("\(WorkoutFormat.set(set.weight, set.reps)) \(settings.model.unit.label)")
                                    .font(.system(size: 15)).foregroundStyle(theme.label)
                                Spacer()
                                if set.completedAt != nil {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.success)
                                }
                                if let pr = settings.model.prsByExercise[exerciseId], pr.sessionId == session.id,
                                   pr.weight == set.weight, pr.reps == set.reps {
                                    Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(theme.warning)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        WidgetUI.header(settings.model.exercise(id: exerciseId)?.name ?? "Exercise", theme: theme)
                    }
                }
                if let notes = session.notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.background.ignoresSafeArea())
    }
}

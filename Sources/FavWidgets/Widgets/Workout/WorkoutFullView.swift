import SwiftUI
import FavWidgetsCore

/// Full screen: the active session when there is one; otherwise Start
/// (routines), History (months on demand), PRs and settings.
struct WorkoutFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @State private var summary: WorkoutSummary?

    var body: some View {
        Group {
            if settings.model.activeSession != nil {
                ActiveSessionView(context: context, settings: settings) { summary = $0 }
            } else {
                WorkoutHomeView(context: context, settings: settings)
            }
        }
        .task {
            await settings.loadIfNeeded()
            await context.month(WorkoutMonth.self, context.currentMonth).loadIfNeeded()
            await context.month(WorkoutMonth.self, context.currentMonth.previous).loadIfNeeded()
        }
        .sheet(item: $summary) { summary in
            WorkoutSummaryView(context: context, summary: summary)
        }
        .background(context.theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("Workouts")
    }
}

/// Start + History + PRs.
private struct WorkoutHomeView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>

    @State private var showSettings = false
    @State private var editor: RoutineEditorTarget?
    @State private var selectedSession: WorkoutSession?
    @State private var confirmDeleteRoutine: Routine?
    @State private var oldestMonth: MonthKey

    private struct RoutineEditorTarget: Identifiable {
        let id: UUID
        let routine: Routine?
    }

    init(context: WidgetContext, settings: WidgetStateController<WorkoutSettings>) {
        self.context = context
        self.settings = settings
        _oldestMonth = State(initialValue: context.currentMonth.previous)
    }

    private var theme: WidgetTheme { context.theme }
    private var usesStarters: Bool { settings.model.routines.isEmpty }
    private var routines: [Routine] { usesStarters ? ExerciseCatalog.starterRoutines : settings.model.routines }

    private var months: [MonthKey] {
        var result: [MonthKey] = []
        var month = context.currentMonth
        while month >= oldestMonth {
            result.append(month)
            month = month.previous
        }
        return result
    }

    var body: some View {
        List {
            Group {
                topBar
                startSection
                historySection
                prSection
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .sheet(isPresented: $showSettings) { WorkoutSettingsView(context: context, settings: settings) }
        .sheet(item: $editor) { target in RoutineEditorView(context: context, settings: settings, routine: target.routine) }
        .sheet(item: $selectedSession) { session in WorkoutSessionDetailView(context: context, settings: settings, session: session) }
        .confirmationDialog("Delete routine?", isPresented: Binding(get: { confirmDeleteRoutine != nil }, set: { if !$0 { confirmDeleteRoutine = nil } }), titleVisibility: .visible) {
            Button("Delete \(confirmDeleteRoutine?.name ?? "routine")", role: .destructive) {
                if let routine = confirmDeleteRoutine {
                    settings.update { $0.routines.removeAll { $0.id == routine.id } }
                }
                confirmDeleteRoutine = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteRoutine = nil }
        } message: {
            Text("Past workouts from this routine are kept.")
        }
    }

    // MARK: Top

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetSyncBadge(state: syncState, theme: theme)
            HStack {
                Text("Start a workout").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workout settings")
            }
        }
        .listRowSeparator(.hidden)
    }

    private var syncState: WidgetSyncState {
        for month in months {
            if case .error = context.month(WorkoutMonth.self, month).syncState {
                return context.month(WorkoutMonth.self, month).syncState
            }
        }
        return settings.syncState
    }

    // MARK: Start

    @ViewBuilder
    private var startSection: some View {
        ForEach(routines) { routine in
            Button { start(routine) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(context.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(routine.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                            if usesStarters {
                                Text("Starter")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(theme.secondaryLabel)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(theme.tertiaryBackground))
                            }
                        }
                        Text(routine.items.compactMap { settings.model.exercise(id: $0.exerciseId)?.name }.joined(separator: ", "))
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                    }
                    Spacer()
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .contextMenu {
                Button { editor = RoutineEditorTarget(id: routine.id, routine: usesStarters ? Routine(name: routine.name, items: routine.items) : routine) } label: {
                    Label(usesStarters ? "Copy to my routines" : "Edit", systemImage: "pencil")
                }
                if !usesStarters {
                    Button(role: .destructive) { confirmDeleteRoutine = routine } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        HStack(spacing: 10) {
            WidgetUI.primaryButton("Empty workout", color: context.accent) { start(nil) }
            Button { editor = RoutineEditorTarget(id: UUID(), routine: nil) } label: {
                Text("New routine")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private func start(_ routine: Routine?) {
        let session = routine.map { WorkoutSessionLogic.session(from: $0) } ?? WorkoutSession(name: "Workout")
        settings.update { $0.activeSession = session }
        context.host.haptic(.light)
        context.track("workout_started", ["routine": routine == nil ? "empty" : (usesStarters ? "starter" : "own")])
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        WidgetUI.header("History", theme: theme)
            .padding(.top, 8)
            .listRowSeparator(.hidden)
        ForEach(months, id: \.rawValue) { month in
            WorkoutMonthSection(context: context, settings: settings, monthKey: month, controller: context.month(WorkoutMonth.self, month)) { session in
                selectedSession = session
            }
        }
        Button {
            oldestMonth = oldestMonth.previous
        } label: {
            Text("Earlier months")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(context.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    // MARK: PRs

    @ViewBuilder
    private var prSection: some View {
        let records = settings.model.prsByExercise
            .map { (id: $0.key, name: settings.model.exercise(id: $0.key)?.name ?? $0.key, record: $0.value) }
            .sorted { $0.name < $1.name }
        if !records.isEmpty {
            WidgetUI.header("Personal records", theme: theme)
                .padding(.top, 8)
                .listRowSeparator(.hidden)
            ForEach(records, id: \.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label)
                        Text(WorkoutFormat.shortDate(item.record.date, calendar: context.calendar))
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(WorkoutFormat.set(item.record.weight, item.record.reps))
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(theme.label)
                        Text("e1RM \(WorkoutFormat.weight(item.record.estimatedOneRM)) \(settings.model.unit.label)")
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(.vertical, 2)
                .listRowSeparator(.hidden)
            }
            Color.clear.frame(height: 24).listRowSeparator(.hidden)
        }
    }
}

// MARK: - Summary sheet

struct WorkoutSummaryView: View {
    let context: WidgetContext
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss

    private var theme: WidgetTheme { context.theme }

    var body: some View {
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
                stat("Sets", "\(summary.completedSets)")
                stat("Volume", WorkoutFormat.volume(summary.volume, unit: summary.unit))
            }
            if !summary.newRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetUI.header("New PRs", theme: theme)
                    ForEach(summary.newRecords, id: \.id) { item in
                        Label("New PR: \(item.exercise) \(WorkoutFormat.set(item.record.weight, item.record.reps))", systemImage: "trophy.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.label)
                    }
                }
            }
            Spacer()
            WidgetUI.primaryButton("Done", color: context.accent) { dismiss() }
        }
        .padding(20)
        .background(theme.background.ignoresSafeArea())
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

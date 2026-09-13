import SwiftUI
import FavWidgetsCore

/// What "Finish workout" hands back for the summary sheet.
struct WorkoutSummary: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let completedSets: Int
    let volume: Double
    let unit: WeightUnit
    let newRecords: [(id: String, exercise: String, record: PersonalRecord)]
}

/// The in-progress workout. Every edit goes through `settings.update` so
/// the session survives relaunches exactly as typed.
struct ActiveSessionView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let onFinished: (WorkoutSummary) -> Void

    @State private var restEndsAt: Date?
    @State private var showPicker = false
    @State private var confirmDiscard = false

    private var theme: WidgetTheme { context.theme }
    private var session: WorkoutSession { settings.model.activeSession ?? WorkoutSession(name: "Workout") }
    private var completedCount: Int { WorkoutSessionLogic.completedSetCount(session) }
    /// Nothing ticked and nothing typed: there is nothing to save yet.
    private var isEmptyWorkout: Bool { !session.sets.contains(where: WorkoutSessionLogic.holdsUserData) }

    var body: some View {
        List {
            Group {
                header
                ForEach(WorkoutSessionLogic.orderedExerciseIds(in: session), id: \.self) { exerciseId in
                    exerciseBlock(exerciseId)
                }
                addExerciseRow
                footer
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
        .safeAreaInset(edge: .bottom) {
            RestTimerView(endsAt: $restEndsAt, theme: theme, accent: context.accent) {
                context.host.haptic(.success)
            }
            .animation(.easeInOut(duration: 0.2), value: restEndsAt == nil)
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(context: context, settings: settings) { exercise in
                settings.update { $0.activeSession?.sets.append(SetEntry(exerciseId: exercise.id, reps: 0, weight: 0)) }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive, action: discard)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("No sets were completed, so nothing will be saved.")
        }
        .workoutKeyboardDoneBar()
    }

    // MARK: Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetSyncBadge(state: settings.syncState, theme: theme)
            HStack(alignment: .firstTextBaseline) {
                Text(session.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.label)
                Spacer()
                TimelineView(.periodic(from: session.startedAt, by: 1)) { timeline in
                    Text(WorkoutFormat.duration(timeline.date.timeIntervalSince(session.startedAt)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(context.accent)
                }
            }
            Text("\(completedCount) \(completedCount == 1 ? "set" : "sets") done · \(WorkoutFormat.volume(session.totalVolume, unit: settings.model.unit))")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    private var addExerciseRow: some View {
        Button { showPicker = true } label: {
            Label("Add exercise", systemImage: "plus.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(context.accent)
                .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            WidgetUI.primaryButton("Finish workout", color: context.accent, action: finish)
                .disabled(isEmptyWorkout)
                .opacity(isEmptyWorkout ? 0.5 : 1)
            if completedCount == 0 {
                Button("Discard workout") { confirmDiscard = true }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .listRowSeparator(.hidden)
    }

    // MARK: Exercise blocks

    @ViewBuilder
    private func exerciseBlock(_ exerciseId: String) -> some View {
        let sets = session.sets.filter { $0.exerciseId == exerciseId }
        let name = settings.model.exercise(id: exerciseId)?.name ?? "Exercise"
        let best = settings.model.prsByExercise[exerciseId]
        let targetReps = WorkoutSessionLogic.targetReps(for: exerciseId, in: session, routines: settings.model.routines + ExerciseCatalog.starterRoutines)
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
            Spacer()
            if let best {
                Text("Best \(WorkoutFormat.set(best.weight, best.reps))")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(.top, 10)
        .listRowSeparator(.hidden)
        ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
            SetRowView(
                context: context,
                settings: settings,
                setId: set.id,
                number: index + 1,
                previousHint: best.map { WorkoutFormat.set($0.weight, $0.reps) },
                targetReps: targetReps,
                onCompleted: startRest
            )
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    settings.update { $0.activeSession?.sets.removeAll { $0.id == set.id } }
                    context.host.haptic(.light)
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        Button {
            let next = WorkoutSessionLogic.nextSet(for: exerciseId, in: session)
            settings.update { model in
                // Insert after the exercise's last row so blocks stay contiguous.
                guard var sets = model.activeSession?.sets else { return }
                let at = (sets.lastIndex { $0.exerciseId == exerciseId }).map { $0 + 1 } ?? sets.count
                sets.insert(next, at: at)
                model.activeSession?.sets = sets
            }
            context.host.haptic(.light)
        } label: {
            Label("Add set", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(context.accent)
                .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    // MARK: Actions

    private func startRest() {
        context.host.haptic(.light)
        restEndsAt = Date().addingTimeInterval(TimeInterval(max(5, settings.model.restTimerSeconds)))
        context.track("set_completed")
    }

    private func finish() {
        guard let active = settings.model.activeSession else { return }
        let result = WorkoutSessionLogic.finish(active, existingRecords: settings.model.prsByExercise)
        let unit = settings.model.unit
        // Month first, then clear the active session: if the app dies in
        // between, the workout exists in its month (merge dedups by id).
        let month = context.month(WorkoutMonth.self, MonthKey(active.startedAt, calendar: context.calendar))
        month.update { model in
            model.sessions.removeAll { $0.id == result.session.id }
            model.sessions.append(result.session)
            model.sessions.sort { $0.startedAt < $1.startedAt }
        }
        settings.update { model in
            model.prsByExercise = WorkoutSessionLogic.applying(result.newRecords, to: model.prsByExercise)
            model.activeSession = nil
        }
        restEndsAt = nil
        context.host.haptic(.success)
        context.track("workout_finished", [
            "sets": String(WorkoutSessionLogic.completedSetCount(result.session)),
            "prs": String(result.newRecords.count)
        ])
        let records = result.newRecords
            .map { (id: $0.key, exercise: settings.model.exercise(id: $0.key)?.name ?? $0.key, record: $0.value) }
            .sorted { $0.exercise < $1.exercise }
        onFinished(WorkoutSummary(
            name: result.session.name,
            duration: WorkoutSessionLogic.duration(of: result.session),
            completedSets: WorkoutSessionLogic.completedSetCount(result.session),
            volume: result.session.totalVolume,
            unit: unit,
            newRecords: records
        ))
    }

    private func discard() {
        guard completedCount == 0 else { return }
        settings.update { $0.activeSession = nil }
        restEndsAt = nil
        context.track("workout_discarded")
    }
}

// MARK: - Set row

/// One set: number, previous-best hint, weight, reps, warm-up, done.
/// Text lives in local state and is parsed into the model on change so a
/// half-typed "102." is never reformatted under the user's thumb.
private struct SetRowView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let setId: UUID
    let number: Int
    let previousHint: String?
    /// From the routine, shown as the reps placeholder and used when a
    /// row is ticked without typing reps.
    let targetReps: Int?
    let onCompleted: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    private var theme: WidgetTheme { context.theme }
    private var entry: SetEntry? { settings.model.activeSession?.sets.first { $0.id == setId } }
    private var isDone: Bool { entry?.completedAt != nil }
    private var isWarmup: Bool { entry?.isWarmup ?? false }

    var body: some View {
        HStack(spacing: 8) {
            Text(isWarmup ? "W" : "\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isWarmup ? theme.warning : theme.secondaryLabel)
                .frame(width: 24)
            Text(previousHint ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
            HStack(spacing: 4) {
                TextField("0", text: $weightText)
                    .widgetDecimalKeyboard()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 56)
                Text(settings.model.unit.label).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
            }
            TextField(targetReps.map(String.init) ?? "reps", text: $repsText)
                .widgetNumberKeyboard()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 56)
            Button {
                mutate { $0.isWarmup.toggle() }
            } label: {
                Text("W")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isWarmup ? .white : theme.secondaryLabel)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isWarmup ? theme.warning : theme.tertiaryBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWarmup ? "Warm-up set" : "Mark as warm-up")
            Button(action: toggleDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isDone ? .white : theme.secondaryLabel)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isDone ? theme.success : theme.tertiaryBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Completed" : "Complete set")
        }
        .padding(.vertical, 2)
        .opacity(isDone ? 0.75 : 1)
        .onAppear(perform: seed)
        .onChange(of: weightText) { text in
            guard let value = WorkoutFormat.parseDecimal(text) ?? (text.isEmpty ? 0 : nil) else { return }
            mutate { $0.weight = value }
        }
        .onChange(of: repsText) { text in
            guard let value = WorkoutFormat.parseInt(text) ?? (text.isEmpty ? 0 : nil) else { return }
            mutate { $0.reps = value }
        }
    }

    private func seed() {
        guard let entry else { return }
        weightText = WorkoutFormat.decimalText(entry.weight)
        repsText = entry.reps == 0 ? "" : String(entry.reps)
    }

    private func mutate(_ change: (inout SetEntry) -> Void) {
        settings.update { model in
            guard let index = model.activeSession?.sets.firstIndex(where: { $0.id == setId }) else { return }
            change(&model.activeSession!.sets[index])
        }
    }

    private func toggleDone() {
        let completing = !isDone
        let fillReps = completing && (entry?.reps ?? 0) == 0 ? targetReps : nil
        mutate {
            $0.completedAt = completing ? Date() : nil
            if let fillReps { $0.reps = fillReps }
        }
        if let fillReps { repsText = String(fillReps) }
        if completing { onCompleted() }
    }
}

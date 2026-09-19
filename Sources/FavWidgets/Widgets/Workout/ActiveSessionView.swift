import SwiftUI
import FavWidgetsCore

/// What "Finish workout" hands back for the summary sheet.
struct WorkoutSummary: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let completedSets: Int
    let unit: WeightUnit
    let newRecords: [(id: String, exercise: String, record: PersonalRecord)]
    /// Best sets, cardio and PR count: the summary sheet, the share text
    /// and the Inner Circle post all read from this.
    let share: WorkoutShareSummary
}

/// The in-progress workout. Every edit goes through `settings.update` so
/// the session survives relaunches exactly as typed.
struct ActiveSessionView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let onFinished: (WorkoutSummary) -> Void
    /// The navigation bar's Back was tapped: show the widget's home page
    /// with the workout still running.
    let onBack: () -> Void

    @State private var restEndsAt: Date?
    @State private var showPicker = false
    @State private var showReorder = false
    @State private var confirmDiscard = false
    @State private var photoTarget: PhotoTarget?

    private struct PhotoTarget: Identifiable { let id: String }
    /// The list has scrolled past the header: the pinned time bar shrinks.
    @State private var isCompact = false

    private var theme: WidgetTheme { context.theme }
    private var session: WorkoutSession { settings.model.activeSession ?? WorkoutSession(name: "Workout") }
    private var completedCount: Int { WorkoutSessionLogic.completedSetCount(session) }
    private var exerciseIds: [String] { WorkoutSessionLogic.orderedExerciseIds(in: session) }
    /// Nothing ticked and nothing typed: there is nothing to save yet.
    private var isEmptyWorkout: Bool { !WorkoutSessionLogic.hasUserData(session) }
    private var cardioIds: [UUID] { session.cardio.map(\.id) }
    private var autoRest: Bool { settings.model.autoRestTimer }

    var body: some View {
        List {
            Group {
                header
                ForEach(exerciseIds, id: \.self) { exerciseId in
                    exerciseBlock(exerciseId)
                }
                if !cardioIds.isEmpty {
                    Text("Cardio").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
                        .padding(.top, 10).listRowSeparator(.hidden)
                    ForEach(cardioIds, id: \.self) { id in
                        CardioRowView(context: context, settings: settings, entryId: id, onCompleted: { context.host.haptic(.light); context.track("cardio_completed") })
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    settings.update { $0.activeSession?.cardio.removeAll { $0.id == id } }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                addExerciseRow
                footer
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "session")
        .onPreferenceChange(SessionScrollOffsetKey.self) { y in
            // Hysteresis so the bar doesn't flicker around the threshold
            let compact = isCompact ? y < -8 : y < -40
            if compact != isCompact { withAnimation(.easeInOut(duration: 0.22)) { isCompact = compact } }
        }
        .background(theme.background)
        .safeAreaInset(edge: .top, spacing: 0) { timeBar }
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
        .sheet(isPresented: $showReorder) {
            ExerciseReorderView(context: context, settings: settings)
        }
        .sheet(item: $photoTarget) { target in
            ExercisePhotoSheet(context: context, settings: settings, exerciseId: target.id)
        }
        .onAppear {
            // Back goes to the widget's home page, not out of the widget.
            let back = onBack
            context.handleBack = { back(); return true }
        }
        .onDisappear { context.handleBack = nil }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive, action: discard)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("No sets were completed, so nothing will be saved.")
        }
        .workoutKeyboardDoneBar()
    }

    // MARK: Pinned time bar

    /// Always visible above the list: elapsed time, the workout name, the
    /// rest-timer switch and Finish. Full size at the top of the list,
    /// one compact line once the user scrolls into the sets.
    private var timeBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: isCompact ? 0 : 2) {
                TimelineView(.periodic(from: session.startedAt, by: 1)) { timeline in
                    Text(WorkoutFormat.duration(timeline.date.timeIntervalSince(session.startedAt)))
                        .font(.system(size: isCompact ? 18 : 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(context.accent)
                }
                Text(isCompact ? "\(session.name) · \(completedCount) \(completedCount == 1 ? "set" : "sets")" : session.name)
                    .font(.system(size: isCompact ? 11 : 15, weight: .semibold))
                    .foregroundStyle(isCompact ? theme.secondaryLabel : theme.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: toggleAutoRest) {
                Image(systemName: autoRest ? "timer" : "timer.slash")
                    .font(.system(size: isCompact ? 15 : 17, weight: .semibold))
                    .foregroundStyle(autoRest ? context.accent : theme.secondaryLabel)
                    .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)
                    .background(Circle().fill(theme.tertiaryBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(autoRest ? "Rest timer on — tap to turn off" : "Rest timer off — tap to turn on")
            Button(action: finish) {
                Text("Finish")
                    .font(.system(size: isCompact ? 14 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isCompact ? 14 : 18)
                    .frame(height: isCompact ? 34 : 40)
                    .background(Capsule().fill(context.accent))
            }
            .buttonStyle(.plain)
            .disabled(isEmptyWorkout)
            .opacity(isEmptyWorkout ? 0.5 : 1)
            .accessibilityLabel("Finish workout")
        }
        .padding(.horizontal, 16)
        .padding(.top, isCompact ? 6 : 10)
        .padding(.bottom, isCompact ? 6 : 10)
        .frame(maxWidth: .infinity)
        .background(theme.background.opacity(0.96))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 0.5) }
    }

    // MARK: Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetSyncBadge(state: settings.syncState, theme: theme)
            Text(headerLine)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
        }
        .padding(.vertical, 4)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: SessionScrollOffsetKey.self, value: proxy.frame(in: .named("session")).minY)
        })
        .listRowSeparator(.hidden)
    }

    private var headerLine: String {
        var parts = ["\(completedCount) \(completedCount == 1 ? "set" : "sets") done"]
        if !exerciseIds.isEmpty { parts.append("\(exerciseIds.count) \(exerciseIds.count == 1 ? "exercise" : "exercises")") }
        let cardio = session.cardioMinutes
        if cardio > 0 { parts.append("\(cardio) min cardio") }
        return parts.joined(separator: " · ")
    }

    private var addExerciseRow: some View {
        HStack {
            Button { showPicker = true } label: {
                Label("Add exercise", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
            Menu {
                ForEach(CardioKind.allCases, id: \.self) { kind in
                    Button { addCardio(kind) } label: { Label(kind.name, systemImage: kind.symbolName) }
                }
            } label: {
                Label("Cardio", systemImage: "figure.run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .frame(minHeight: 48)
                    .padding(.leading, 14)
            }
            Spacer()
            if exerciseIds.count > 1 {
                Button { showReorder = true } label: {
                    Label("Reorder", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reorder exercises")
            }
        }
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
        HStack(alignment: .center, spacing: 10) {
            Button { photoTarget = PhotoTarget(id: exerciseId) } label: {
                ExerciseThumb(url: settings.model.imageURL(for: exerciseId),
                              symbolName: settings.model.exercise(id: exerciseId)?.symbolName ?? "dumbbell.fill",
                              accent: context.accent, theme: theme, size: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if settings.model.imageURL(for: exerciseId) == nil {
                            Image(systemName: "camera.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .padding(3).background(Circle().fill(context.accent)).offset(x: 3, y: 3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a photo for \(name)")
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

    private func addCardio(_ kind: CardioKind) {
        settings.update { $0.activeSession?.cardio.append(CardioEntry(kind: kind)) }
        context.host.haptic(.light)
        context.track("cardio_added", ["kind": kind.rawValue])
    }

    private func startRest() {
        context.host.haptic(.light)
        context.track("set_completed")
        guard autoRest else { return }
        restEndsAt = Date().addingTimeInterval(TimeInterval(max(5, settings.model.restTimerSeconds)))
    }

    private func toggleAutoRest() {
        let on = !autoRest
        settings.update { $0.autoRestTimer = on }
        if !on { restEndsAt = nil }     // turning it off also stops the one running
        context.host.haptic(.light)
        context.track("workout_auto_rest_changed", ["on": on ? "1" : "0"])
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
        let share = WorkoutShareSummary.make(session: result.session, newRecords: result.newRecords, unit: unit,
                                             weightKg: settings.model.profile.weightKg) { settings.model.exercise(id: $0)?.name ?? "Exercise" }
        onFinished(WorkoutSummary(
            name: result.session.name,
            duration: WorkoutSessionLogic.duration(of: result.session),
            completedSets: WorkoutSessionLogic.completedSetCount(result.session),
            unit: unit,
            newRecords: records,
            share: share
        ))
    }

    private func discard() {
        guard completedCount == 0 else { return }
        settings.update { $0.activeSession = nil }
        restEndsAt = nil
        context.track("workout_discarded")
    }
}

/// Header row's y in the list's coordinate space; negative once scrolled.
private struct SessionScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Reorder sheet

/// Drag the exercises of the active session into a new order. Whole blocks
/// move; the sets inside each keep their order.
private struct ExerciseReorderView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @Environment(\.dismiss) private var dismiss

    private var theme: WidgetTheme { context.theme }
    private var session: WorkoutSession { settings.model.activeSession ?? WorkoutSession(name: "Workout") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reorder exercises").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
                Spacer()
                Button("Done") { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.primary)
            }
            .padding(20)
            List {
                ForEach(WorkoutSessionLogic.orderedExerciseIds(in: session), id: \.self) { id in
                    let count = session.sets.filter { $0.exerciseId == id }.count
                    HStack {
                        Text(settings.model.exercise(id: id)?.name ?? "Exercise")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                        Spacer()
                        Text("\(count) \(count == 1 ? "set" : "sets")")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    let moved = WorkoutSessionLogic.movingExercises(in: session, fromOffsets: source, toOffset: destination)
                    settings.update { $0.activeSession?.sets = moved }
                    context.host.haptic(.light)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
        }
        .background(theme.background.ignoresSafeArea())
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

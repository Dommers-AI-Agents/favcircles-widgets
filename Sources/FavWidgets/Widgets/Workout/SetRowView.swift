import SwiftUI
import FavWidgetsCore

/// One set: number, previous-best hint, weight, reps, warm-up, done.
/// Text lives in local state and is parsed into the model on change so a
/// half-typed "102." is never reformatted under the user's thumb.
struct SetRowView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let setId: UUID
    let number: Int
    let previousHint: String?
    /// What this row offers before anyone types: the last completed set of
    /// this exercise, or the routine's remembered values. Shown as the
    /// placeholders, and written in when the row is ticked untouched.
    let target: WorkoutSessionLogic.SetTarget
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
                TextField(target.weight.map(WorkoutNumber.trim) ?? "0", text: $weightText)
                    .widgetDecimalKeyboard()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 56)
                Text(settings.model.unit.label).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
            }
            TextField(target.reps.map(String.init) ?? "reps", text: $repsText)
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
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDone ? theme.success.opacity(0.16) : Color.clear)
        )
        .overlay(alignment: .leading) {
            // A done set should read as done at a glance, from across the
            // row — the tick alone is easy to miss mid-workout.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isDone ? theme.success : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .animation(.easeInOut(duration: 0.18), value: isDone)
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

    /// Ticking an untouched row commits what it was offering, so a repeat
    /// workout is all ticks: the reps AND the weight, not just the reps.
    private func toggleDone() {
        let completing = !isDone
        let fillReps = completing && (entry?.reps ?? 0) == 0 ? target.reps : nil
        let fillWeight = completing && (entry?.weight ?? 0) == 0 ? target.weight : nil
        mutate {
            $0.completedAt = completing ? Date() : nil
            if let fillReps { $0.reps = fillReps }
            if let fillWeight { $0.weight = fillWeight }
        }
        if let fillReps { repsText = String(fillReps) }
        if let fillWeight { weightText = WorkoutFormat.decimalText(fillWeight) }
        if completing { onCompleted() }
    }
}

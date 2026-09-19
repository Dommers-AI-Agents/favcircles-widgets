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

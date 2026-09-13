import SwiftUI
import FavWidgetsCore

/// Create or edit a routine: name, exercises, target sets/reps.
struct RoutineEditorView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @State private var draft: Routine
    @State private var showPicker = false
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool

    init(context: WidgetContext, settings: WidgetStateController<WorkoutSettings>, routine: Routine?) {
        self.context = context
        self.settings = settings
        _draft = State(initialValue: routine ?? Routine(name: ""))
        isNew = routine == nil
    }

    private var theme: WidgetTheme { context.theme }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.items.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.foregroundStyle(theme.secondaryLabel)
                Spacer()
                Text(isNew ? "New routine" : "Edit routine").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
                Spacer()
                Button("Save", action: save)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSave ? theme.primary : theme.secondaryLabel)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            List {
                TextField("Routine name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                WidgetUI.header("Exercises", theme: theme)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                ForEach($draft.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.model.exercise(id: item.exerciseId)?.name ?? "Exercise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.label)
                        HStack(spacing: 16) {
                            Stepper("\(item.targetSets) sets", value: $item.targetSets, in: 1...10)
                            Stepper("\(item.targetReps) reps", value: $item.targetReps, in: 1...100)
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            draft.items.removeAll { $0.id == item.id }
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    showPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(context.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(context: context, settings: settings) { exercise in
                draft.items.append(RoutineItem(exerciseId: exercise.id))
            }
        }
    }

    private func save() {
        var routine = draft
        routine.name = routine.name.trimmingCharacters(in: .whitespaces)
        settings.update { model in
            if let index = model.routines.firstIndex(where: { $0.id == routine.id }) {
                model.routines[index] = routine
            } else {
                model.routines.append(routine)
            }
        }
        context.host.haptic(.success)
        context.track("routine_saved", ["new": isNew ? "1" : "0"])
        dismiss()
    }
}

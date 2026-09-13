import SwiftUI
import FavWidgetsCore

/// Pick an exercise (built-in + custom, grouped by muscle) or create one.
struct ExercisePickerView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var newGroup = ""

    private var theme: WidgetTheme { context.theme }

    private var groups: [(name: String, exercises: [Exercise])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = settings.model.allExercises.filter { query.isEmpty || $0.name.lowercased().contains(query) }
        let byGroup = Dictionary(grouping: matching, by: \.muscleGroup)
        return byGroup.keys.sorted().map { (name: $0, exercises: byGroup[$0]!.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add exercise").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
                Spacer()
                Button("Cancel") { dismiss() }.foregroundStyle(theme.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            TextField("Search exercises", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            List {
                createRow.listRowBackground(Color.clear)
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.exercises) { exercise in
                            Button {
                                pick(exercise)
                            } label: {
                                HStack {
                                    Text(exercise.name).font(.system(size: 16)).foregroundStyle(theme.label)
                                    Spacer()
                                    if !ExerciseCatalog.builtIn.contains(where: { $0.id == exercise.id }) {
                                        Text("Custom").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                                    }
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        WidgetUI.header(group.name, theme: theme)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var createRow: some View {
        if creating {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Exercise name", text: $newName).textFieldStyle(.roundedBorder)
                TextField("Muscle group (e.g. Chest)", text: $newGroup).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { creating = false }.foregroundStyle(theme.secondaryLabel)
                    Spacer()
                    Button("Create", action: create)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(newName.trimmingCharacters(in: .whitespaces).isEmpty ? theme.secondaryLabel : theme.primary)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.vertical, 6)
        } else {
            Button {
                creating = true
                newName = search
            } label: {
                Label("Create exercise", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let group = newGroup.trimmingCharacters(in: .whitespaces)
        let exercise = Exercise(name: name, muscleGroup: group.isEmpty ? "Other" : group)
        settings.update { $0.customExercises.append(exercise) }
        context.track("exercise_created")
        pick(exercise)
    }

    private func pick(_ exercise: Exercise) {
        context.host.haptic(.light)
        onPick(exercise)
        dismiss()
    }
}

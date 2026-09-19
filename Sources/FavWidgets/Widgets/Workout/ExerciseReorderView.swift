import SwiftUI
import FavWidgetsCore

/// Drag the exercises of the active session into a new order. Whole blocks
/// move; the sets inside each keep their order.
struct ExerciseReorderView: View {
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
                    let count = session.sets.reduce(0) { $0 + ($1.exerciseId == id ? 1 : 0) }
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

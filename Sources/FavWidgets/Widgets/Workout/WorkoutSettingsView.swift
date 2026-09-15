import SwiftUI
import FavWidgetsCore

/// Unit and rest-timer length.
struct WorkoutSettingsView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @Environment(\.dismiss) private var dismiss

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Workout settings").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
                Spacer()
                Button("Done") { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.primary)
            }
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.header("Weight unit", theme: theme)
                // Display-only: the unit labels what the user types; stored
                // numbers are never converted when this changes.
                Picker("Unit", selection: Binding(
                    get: { settings.model.unit },
                    set: { unit in settings.update { $0.unit = unit }; context.track("workout_unit_changed", ["unit": unit.rawValue]) }
                )) {
                    ForEach(WeightUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Labels only — existing numbers aren't converted.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.header("Rest timer", theme: theme)
                Toggle(isOn: Binding(
                    get: { settings.model.autoRestTimer },
                    set: { on in settings.update { $0.autoRestTimer = on }; context.track("workout_auto_rest_changed", ["on": on ? "1" : "0"]) }
                )) {
                    Text("Start a rest timer after each set")
                        .font(.system(size: 15)).foregroundStyle(theme.label)
                }
                .tint(context.accent)
                Picker("Rest timer", selection: Binding(
                    get: { settings.model.restTimerSeconds },
                    set: { seconds in settings.update { $0.restTimerSeconds = seconds } }
                )) {
                    ForEach([60, 90, 120, 180], id: \.self) { Text(WorkoutFormat.duration(TimeInterval($0))).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.model.autoRestTimer)
                .opacity(settings.model.autoRestTimer ? 1 : 0.4)
            }
            Spacer()
        }
        .padding(20)
        .background(theme.background.ignoresSafeArea())
    }
}

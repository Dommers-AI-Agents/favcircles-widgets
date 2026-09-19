import SwiftUI
import FavWidgetsCore

/// Unit, rest timer, and the body profile behind calorie estimates.
struct WorkoutSettingsView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var feetText = ""
    @State private var inchesText = ""
    @State private var cmText = ""
    @State private var birthYearText = ""

    private var theme: WidgetTheme { context.theme }
    private var unit: WeightUnit { settings.model.unit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Workout settings").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
                    Spacer()
                    Button("Done") { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.primary)
                }
                unitSection
                profileSection
                restSection
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear(perform: seed)
        .workoutKeyboardDoneBar()
    }

    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Units", theme: theme)
            // Display-only: the unit labels what the user types; stored
            // numbers are never converted when this changes.
            Picker("Unit", selection: Binding(
                get: { settings.model.unit },
                set: { unit in settings.update { $0.unit = unit }; context.track("workout_unit_changed", ["unit": unit.rawValue]); seed() }
            )) {
                ForEach(WeightUnit.allCases, id: \.self) { Text($0 == .lb ? "lb · mi · ft" : "kg · km · cm").tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Labels only — existing lifts aren't converted.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("About you", theme: theme)
            HStack(spacing: 10) {
                labeled("Weight (\(unit.label))") {
                    TextField(unit == .lb ? "172" : "78", text: $weightText)
                        .widgetDecimalKeyboard().textFieldStyle(.roundedBorder).frame(width: 90)
                        .onChange(of: weightText) { t in
                            if t.isEmpty { settings.update { $0.profile.weightKg = nil }; return }
                            guard let v = WorkoutFormat.parseDecimal(t), v > 0 else { return }
                            settings.update { $0.profile.weightKg = unit == .lb ? WorkoutCardioLogic.kg(fromLb: v) : v }
                        }
                }
                if unit == .lb {
                    labeled("Height") {
                        HStack(spacing: 4) {
                            TextField("5", text: $feetText).widgetNumberKeyboard().textFieldStyle(.roundedBorder).frame(width: 46)
                            Text("ft").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                            TextField("11", text: $inchesText).widgetNumberKeyboard().textFieldStyle(.roundedBorder).frame(width: 46)
                            Text("in").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        .onChange(of: feetText) { _ in saveHeightImperial() }
                        .onChange(of: inchesText) { _ in saveHeightImperial() }
                    }
                } else {
                    labeled("Height (cm)") {
                        TextField("180", text: $cmText).widgetNumberKeyboard().textFieldStyle(.roundedBorder).frame(width: 80)
                            .onChange(of: cmText) { t in
                                if t.isEmpty { settings.update { $0.profile.heightCm = nil }; return }
                                guard let v = WorkoutFormat.parseDecimal(t), v > 0 else { return }
                                settings.update { $0.profile.heightCm = v }
                            }
                    }
                }
            }
            HStack(spacing: 10) {
                labeled("Birth year") {
                    TextField("1985", text: $birthYearText).widgetNumberKeyboard().textFieldStyle(.roundedBorder).frame(width: 80)
                        .onChange(of: birthYearText) { t in
                            if t.isEmpty { settings.update { $0.profile.birthYear = nil }; return }
                            guard let v = WorkoutFormat.parseInt(t), v > 1900, v < 2100 else { return }
                            settings.update { $0.profile.birthYear = v }
                        }
                }
                labeled("Sex") {
                    Picker("Sex", selection: Binding(get: { settings.model.profile.sex ?? "" }, set: { v in settings.update { $0.profile.sex = v.isEmpty ? nil : v } })) {
                        Text("—").tag("")
                        Text("Female").tag("female")
                        Text("Male").tag("male")
                    }
                    .pickerStyle(.menu)
                    .tint(theme.label)
                }
            }
            Text("Used for the calorie estimate on cardio. Kept in your own widget data, never shown to anyone.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var restSection: some View {
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
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
            content()
        }
    }

    private func seed() {
        let p = settings.model.profile
        if let kg = p.weightKg {
            weightText = WorkoutFormat.weight(unit == .lb ? WorkoutCardioLogic.lb(fromKg: kg) : kg)
        } else { weightText = "" }
        if let cm = p.heightCm {
            let (f, i) = WorkoutCardioLogic.feetInches(fromCm: cm)
            feetText = String(f); inchesText = String(i); cmText = String(Int(cm.rounded()))
        } else { feetText = ""; inchesText = ""; cmText = "" }
        birthYearText = p.birthYear.map(String.init) ?? ""
    }

    private func saveHeightImperial() {
        guard let feet = WorkoutFormat.parseInt(feetText) else {
            if feetText.isEmpty && inchesText.isEmpty { settings.update { $0.profile.heightCm = nil } }
            return
        }
        let inches = WorkoutFormat.parseDecimal(inchesText) ?? 0
        settings.update { $0.profile.heightCm = WorkoutCardioLogic.cm(feet: feet, inches: inches) }
    }
}

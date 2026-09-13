import SwiftUI
import FavWidgetsCore

/// Daily goal and optional macro goals. Every keystroke that parses is
/// written straight to the settings document.
struct CalorieSettingsView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<CalorieSettings>
    @Environment(\.dismiss) private var dismiss

    @State private var goal = ""
    @State private var macrosOn = false
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Calorie settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.label)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.header("Daily goal", theme: theme)
                HStack {
                    TextField("2000", text: $goal)
                        .widgetNumberKeyboard()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("kcal").foregroundStyle(theme.secondaryLabel)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $macrosOn) {
                    Text("Macro goals").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label)
                }
                .tint(context.accent)
                if macrosOn {
                    HStack(spacing: 8) {
                        field("Protein g", text: $protein)
                        field("Carbs g", text: $carbs)
                        field("Fat g", text: $fat)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(theme.background.ignoresSafeArea())
        .onAppear(perform: seed)
        .onChange(of: goal) { text in
            guard let value = CalorieNumberParsing.integer(text), value > 0, value != settings.model.dailyGoalKcal else { return }
            settings.update { $0.dailyGoalKcal = value }
            context.track("calorie_goal_changed")
        }
        .onChange(of: macrosOn) { on in
            if on {
                let current = settings.model.macroGoals ?? MacroTotals(kcal: settings.model.dailyGoalKcal, protein: 150, carbs: 250, fat: 70)
                settings.update { $0.macroGoals = current }
                protein = CalorieNumberParsing.text(current.protein)
                carbs = CalorieNumberParsing.text(current.carbs)
                fat = CalorieNumberParsing.text(current.fat)
            } else {
                settings.update { $0.macroGoals = nil }
            }
        }
        .onChange(of: protein) { updateMacro(\.protein, $0) }
        .onChange(of: carbs) { updateMacro(\.carbs, $0) }
        .onChange(of: fat) { updateMacro(\.fat, $0) }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .widgetDecimalKeyboard()
            .textFieldStyle(.roundedBorder)
    }

    private func seed() {
        goal = String(settings.model.dailyGoalKcal)
        if let goals = settings.model.macroGoals {
            macrosOn = true
            protein = CalorieNumberParsing.text(goals.protein)
            carbs = CalorieNumberParsing.text(goals.carbs)
            fat = CalorieNumberParsing.text(goals.fat)
        }
    }

    private func updateMacro(_ path: WritableKeyPath<MacroTotals, Double>, _ text: String) {
        guard let value = CalorieNumberParsing.decimal(text) else { return }
        settings.update { $0.macroGoals?[keyPath: path] = value }
    }
}

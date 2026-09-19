import SwiftUI
import FavWidgetsCore

/// Name + kcal, expandable macros, Add. Lives at the top so the card's
/// "+ Add" lands here.
struct CalorieQuickAddRow: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<CalorieSettings>
    @ObservedObject var month: WidgetStateController<CalorieMonth>
    let day: DayKey

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showMacros = false
    @FocusState private var focused: Field?

    private enum Field { case name, kcal, protein, carbs, fat }

    private var theme: WidgetTheme { context.theme }

    private var parsedKcal: Int? {
        let trimmed = kcal.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedKcal != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Quick add", theme: theme)
            HStack(spacing: 8) {
                TextField("Food", text: $name)
                    .focused($focused, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focused = .kcal }
                    .textFieldStyle(.roundedBorder)
                TextField("kcal", text: $kcal)
                    .focused($focused, equals: .kcal)
                    .widgetNumberKeyboard()
                    .submitLabel(.done)
                    .onSubmit(add)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button(action: add) {
                    Text("Add")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(canAdd ? context.accent : theme.tertiaryBackground))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMacros.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showMacros ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold))
                    Text("Macros").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.secondaryLabel)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            if showMacros {
                HStack(spacing: 8) {
                    macroField("Protein g", text: $protein, field: .protein)
                    macroField("Carbs g", text: $carbs, field: .carbs)
                    macroField("Fat g", text: $fat, field: .fat)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    private func macroField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .focused($focused, equals: field)
            .widgetDecimalKeyboard()
            .textFieldStyle(.roundedBorder)
    }

    private func add() {
        guard canAdd, let kcalValue = parsedKcal else { return }
        let entry = FoodEntry(
            name: name.trimmingCharacters(in: .whitespaces),
            kcal: kcalValue,
            protein: CalorieNumberParsing.decimal(protein),
            carbs: CalorieNumberParsing.decimal(carbs),
            fat: CalorieNumberParsing.decimal(fat),
            loggedAt: CalorieFormat.loggedAt(for: day, today: context.today, calendar: context.calendar)
        )
        month.update { $0.add(entry, on: day) }
        settings.update { $0.noteRecent(entry) }
        context.host.haptic(.light)
        context.track("food_logged", ["source": "quick_add", "has_macros": entry.protein != nil || entry.carbs != nil || entry.fat != nil ? "1" : "0"])
        name = ""; kcal = ""; protein = ""; carbs = ""; fat = ""
        focused = .name
    }
}

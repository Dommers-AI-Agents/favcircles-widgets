import SwiftUI
import FavWidgetsCore

/// Full screen: a day at a time (arrows cross months and load the other
/// month on demand), quick-add at the top, recents, the day's entries with
/// swipe-to-delete, and a 7-day bar row.
struct CalorieFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<CalorieSettings>
    @State private var day: DayKey
    @State private var showSettings = false

    init(context: WidgetContext, settings: WidgetStateController<CalorieSettings>) {
        self.context = context
        self.settings = settings
        _day = State(initialValue: context.today)
    }

    var body: some View {
        CalorieDayView(
            context: context,
            settings: settings,
            month: context.month(CalorieMonth.self, day.monthKey),
            weekMonth: context.month(CalorieMonth.self, day.adding(days: -6, calendar: context.calendar).monthKey),
            day: $day,
            showSettings: $showSettings
        )
        .task(id: day) {
            // Unstructured so a quick day step doesn't cancel an in-flight
            // load (reload() would record the cancellation as an error).
            // loadIfNeeded is a no-op once loaded, so per-day is cheap.
            let month = context.month(CalorieMonth.self, day.monthKey)
            let weekMonth = context.month(CalorieMonth.self, day.adding(days: -6, calendar: context.calendar).monthKey)
            Task { @MainActor in
                await settings.loadIfNeeded()
                await month.loadIfNeeded()
                await weekMonth.loadIfNeeded()
            }
        }
        .sheet(isPresented: $showSettings) {
            CalorieSettingsView(context: context, settings: settings)
        }
        .background(context.theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("Calories")
    }
}

/// Everything for the selected day. Rebuilt with the right month
/// controllers whenever `day` changes.
private struct CalorieDayView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<CalorieSettings>
    @ObservedObject var month: WidgetStateController<CalorieMonth>
    @ObservedObject var weekMonth: WidgetStateController<CalorieMonth>
    @Binding var day: DayKey
    @Binding var showSettings: Bool

    private var theme: WidgetTheme { context.theme }
    private var totals: MacroTotals { month.model.totals(on: day) }
    private var goal: Int { settings.model.dailyGoalKcal }

    private var syncState: WidgetSyncState {
        for state in [month.syncState, weekMonth.syncState] {
            if case .error = state { return state }
        }
        return settings.syncState
    }

    var body: some View {
        List {
            Group {
                header
                summary
                CalorieQuickAddRow(context: context, settings: settings, month: month, day: day)
                if !settings.model.recentFoods.isEmpty {
                    recents
                }
                entries
                weekRow
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetSyncBadge(state: syncState, theme: theme)
            HStack(spacing: 12) {
                dayArrow("chevron.left", days: -1)
                Text(CalorieFormat.dayTitle(day, today: context.today, calendar: context.calendar))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.label)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if day != context.today { day = context.today } }
                dayArrow("chevron.right", days: 1)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Calorie settings")
            }
        }
        .listRowSeparator(.hidden)
    }

    private func dayArrow(_ symbol: String, days: Int) -> some View {
        Button {
            context.host.haptic(.light)
            day = day.adding(days: days, calendar: context.calendar)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.label)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(days < 0 ? "Previous day" : "Next day")
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .center, spacing: 16) {
            CalorieRingView(consumed: totals.kcal, goal: goal, theme: theme, accent: context.accent, size: 96, lineWidth: 10)
            VStack(alignment: .leading, spacing: 8) {
                let remaining = goal - totals.kcal
                Text(remaining >= 0 ? "\(CalorieFormat.kcal(remaining)) left" : "\(CalorieFormat.kcal(-remaining)) over")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(remaining >= 0 ? theme.label : theme.warning)
                Text("of \(CalorieFormat.kcal(goal)) kcal")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryLabel)
                if let goals = settings.model.macroGoals {
                    macroBar("P", value: totals.protein, goal: goals.protein)
                    macroBar("C", value: totals.carbs, goal: goals.carbs)
                    macroBar("F", value: totals.fat, goal: goals.fat)
                } else if let line = CalorieFormat.macroLine(totals) {
                    Text(line).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private func macroBar(_ letter: String, value: Double, goal: Double) -> some View {
        HStack(spacing: 8) {
            Text(letter)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.secondaryLabel)
                .frame(width: 14, alignment: .leading)
            WidgetUI.progressBar(fraction: goal > 0 ? value / goal : 0, color: context.accent, theme: theme)
            Text("\(CalorieFormat.grams(value)) / \(CalorieFormat.grams(goal))")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel)
                .frame(width: 88, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Recent", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(settings.model.recentFoods) { preset in
                        recentChip(preset)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func recentChip(_ preset: FoodPreset) -> some View {
        Button {
            let entry = preset.entry(at: CalorieFormat.loggedAt(for: day, today: context.today, calendar: context.calendar))
            month.update { $0.add(entry, on: day) }
            settings.update { $0.noteRecent(entry) }
            context.host.haptic(.light)
            context.track("food_logged", ["source": "recent"])
        } label: {
            HStack(spacing: 4) {
                Text(preset.name).font(.system(size: 13, weight: .semibold))
                Text("\(CalorieFormat.kcal(preset.kcal))").font(.system(size: 12))
            }
            .foregroundStyle(theme.label)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(theme.secondaryBackground))
        }
        .buttonStyle(.plain)
        .contextMenu {
            // A UX list only: removing a chip never touches logged entries.
            Button(role: .destructive) {
                settings.update { $0.recentFoods.removeAll { $0.id == preset.id } }
            } label: {
                Label("Remove from recents", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: Entries

    @ViewBuilder
    private var entries: some View {
        let items = month.model.entries(on: day)
        WidgetUI.header(day == context.today ? "Today" : "Logged", theme: theme)
            .listRowSeparator(.hidden)
        if items.isEmpty {
            Text("Nothing logged yet")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .listRowSeparator(.hidden)
        }
        ForEach(items) { entry in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.label)
                    if let line = CalorieFormat.macroLine(entry.macros) {
                        Text(line).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                Spacer()
                Text("\(CalorieFormat.kcal(entry.kcal)) kcal")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.label)
            }
            .padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    month.update { $0.remove(id: entry.id, on: day) }
                    context.host.haptic(.light)
                    context.track("food_deleted")
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Week

    private var weekRow: some View {
        let days = (0..<7).map { day.adding(days: $0 - 6, calendar: context.calendar) }
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Last 7 days", theme: theme)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.rawValue) { d in
                    let kcal = (d.monthKey == day.monthKey ? month : weekMonth).model.totals(on: d).kcal
                    let fraction = goal > 0 ? Double(kcal) / Double(goal) : 0
                    VStack(spacing: 4) {
                        Text(kcal > 0 ? CalorieFormat.kcal(kcal) : "–")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.secondaryLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.tertiaryBackground).frame(height: 56)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(kcal > goal ? theme.warning : context.accent)
                                .frame(height: max(kcal > 0 ? 3 : 0, min(1, fraction) * 56))
                        }
                        Text(CalorieFormat.weekdayLetter(d, calendar: context.calendar))
                            .font(.system(size: 11, weight: d == day ? .bold : .regular))
                            .foregroundStyle(d == day ? theme.label : theme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { day = d }
                    .accessibilityLabel("\(d.rawValue): \(kcal) calories")
                }
            }
        }
        .padding(.bottom, 24)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Quick add

/// Name + kcal, expandable macros, Add. Lives at the top so the card's
/// "+ Add" lands here.
private struct CalorieQuickAddRow: View {
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

/// Lenient number parsing for typed fields ("1,5" and "1.5" both work).
enum CalorieNumberParsing {
    static func decimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0, value.isFinite else { return nil }
        return value
    }

    static func integer(_ text: String) -> Int? {
        guard let value = decimal(text) else { return nil }
        return Int(value.rounded())
    }

    static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

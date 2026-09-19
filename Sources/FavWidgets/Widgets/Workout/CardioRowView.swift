import SwiftUI
import PhotosUI
import FavWidgetsCore

/// One cardio entry in the active session: machine, minutes, distance,
/// effort, calories (typed or estimated), done.
struct CardioRowView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let entryId: UUID
    let onCompleted: () -> Void

    @State private var minutesText = ""
    @State private var distanceText = ""
    @State private var caloriesText = ""

    private var theme: WidgetTheme { context.theme }
    private var entry: CardioEntry? { settings.model.activeSession?.cardio.first { $0.id == entryId } }
    private var isDone: Bool { entry?.completedAt != nil }

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: entry.kind.symbolName).font(.system(size: 18, weight: .semibold)).foregroundStyle(context.accent).frame(width: 28)
                    Text(entry.kind.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
                    Spacer()
                    Picker("Effort", selection: Binding(get: { entry.intensity }, set: { v in mutate { $0.intensity = v } })) {
                        ForEach(CardioIntensity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.secondaryLabel)
                }
                HStack(spacing: 8) {
                    field("min", text: $minutesText, width: 64)
                    if entry.kind.tracksDistance { field(settings.model.distanceUnit, text: $distanceText, width: 72, decimal: true) }
                    field("kcal", text: $caloriesText, width: 72)
                    if entry.calories == nil, let est = WorkoutCardioLogic.calories(for: entry, weightKg: settings.model.profile.weightKg) {
                        Text("≈\(est)").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    } else if entry.calories == nil && settings.model.profile.weightKg == nil {
                        Text("add weight in settings for an estimate").font(.system(size: 10)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                    }
                    Spacer()
                    Button(action: toggleDone) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isDone ? .white : theme.secondaryLabel)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isDone ? theme.success : theme.tertiaryBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .opacity(isDone ? 0.75 : 1)
            .onAppear(perform: seed)
            .onChange(of: minutesText) { t in if let v = WorkoutFormat.parseInt(t) ?? (t.isEmpty ? 0 : nil) { mutate { $0.minutes = v } } }
            .onChange(of: distanceText) { t in if let v = WorkoutFormat.parseDecimal(t) ?? (t.isEmpty ? 0 : nil) { mutate { $0.distance = v > 0 ? v : nil } } }
            .onChange(of: caloriesText) { t in if let v = WorkoutFormat.parseInt(t) ?? (t.isEmpty ? 0 : nil) { mutate { $0.calories = v > 0 ? v : nil } } }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, width: CGFloat, decimal: Bool = false) -> some View {
        VStack(spacing: 2) {
            Group {
                if decimal {
                    TextField("0", text: text).widgetDecimalKeyboard()
                } else {
                    TextField("0", text: text).widgetNumberKeyboard()
                }
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: width)
            Text(placeholder).font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private func seed() {
        guard let entry else { return }
        minutesText = entry.minutes == 0 ? "" : String(entry.minutes)
        distanceText = entry.distance.map { WorkoutFormat.decimalText($0) } ?? ""
        caloriesText = entry.calories.map(String.init) ?? ""
    }

    private func mutate(_ change: (inout CardioEntry) -> Void) {
        settings.update { model in
            guard let index = model.activeSession?.cardio.firstIndex(where: { $0.id == entryId }) else { return }
            change(&model.activeSession!.cardio[index])
        }
    }

    private func toggleDone() {
        let completing = !isDone
        mutate { $0.completedAt = completing ? Date() : nil }
        if completing { onCompleted() }
    }
}

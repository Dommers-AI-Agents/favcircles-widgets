import SwiftUI
import FavWidgetsCore

struct MedsFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<MedSettings>
    @ObservedObject var month: WidgetStateController<MedMonth>
    @ObservedObject var previous: WidgetStateController<MedMonth>
    @State private var editing: Med?
    @State private var adding = false
    @State private var notificationsOff = false

    private var theme: WidgetTheme { context.theme }
    private var doses: [MedDose] { month.model.doses + previous.model.doses }

    var body: some View {
        let now = Date()
        let meds = settings.model.activeMeds
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if notificationsOff {
                    Label("Notifications are off for FavCircles, so reminders can't show.", systemImage: "bell.slash")
                        .font(.system(size: 13)).foregroundStyle(theme.danger)
                }
                today(meds, now: now)
                adherence(meds, now: now)
                medList
                let dropped = MedPlan.reminders(settings.model.meds).dropped
                if dropped > 0 {
                    Text("iPhone allows a limited number of reminders; \(dropped) won't ring. Fewer times or days will fix it.")
                        .font(.system(size: 12)).foregroundStyle(theme.warning)
                }
                history(meds, now: now)
                Text("Private to you. Reminders are set on this phone; press and hold one to tap Took it without opening the app.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .task {
            await settings.loadIfNeeded(); await month.loadIfNeeded(); await previous.loadIfNeeded()
            notificationsOff = !(await MedReminderScheduler.sync(settings.model))
        }
        .sheet(item: $editing) { med in
            MedEditSheet(context: context, med: med, onSave: { save($0) }, onDelete: { delete(med) })
        }
        .sheet(isPresented: $adding) { MedEditSheet(context: context, med: nil, onSave: { save($0) }, onDelete: nil) }
    }

    // MARK: Today

    private func today(_ meds: [Med], now: Date) -> some View {
        let slots = MedPlan.slots(meds, on: DayKey(now, calendar: context.calendar), calendar: context.calendar)
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Today", theme: theme)
            if slots.isEmpty {
                Text(meds.isEmpty ? "Add a medication below." : "Nothing scheduled today.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(slots) { slot in
                let state = MedPlan.state(slot, doses: doses, now: now)
                HStack(spacing: 10) {
                    Circle().fill(MedColors.color(state, theme: theme, accent: context.accent)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.med.label).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label)
                        Text("\(MedPlan.timeText(slot.minutes, calendar: context.calendar)) · \(stateText(state))")
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                    if state == .taken || state == .skipped {
                        Button("Undo") { MedLogging.mark(slot, nil, context: context) }
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    } else {
                        Button("Skip") { MedLogging.mark(slot, .skipped, context: context) }
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        Button { MedLogging.mark(slot, .taken, context: context) } label: {
                            Text("Took it").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(context.accent))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
            }
        }
    }

    private func stateText(_ s: MedPlan.State) -> String {
        switch s {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .missed: return "Missed"
        case .due: return "Due now"
        case .upcoming: return "Later"
        }
    }

    // MARK: Adherence

    @ViewBuilder
    private func adherence(_ meds: [Med], now: Date) -> some View {
        let week = MedPlan.adherence(meds, doses: doses, days: 7, now: now, calendar: context.calendar)
        let monthRate = MedPlan.adherence(meds, doses: doses, days: 30, now: now, calendar: context.calendar)
        if week != nil || monthRate != nil {
            HStack(spacing: 12) {
                stat("Last 7 days", week)
                stat("Last 30 days", monthRate)
            }
        }
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 4) {
            Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    // MARK: Medications

    private var medList: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Medications", theme: theme)
            ForEach(settings.model.meds) { med in
                Button { editing = med } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.label).font(.system(size: 16, weight: .medium))
                                .foregroundStyle(med.active ? theme.label : theme.secondaryLabel)
                            Text(MedSchedule.summary(med, calendar: context.calendar)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            WidgetUI.primaryButton("Add a medication", color: context.accent) { adding = true }
        }
    }

    // MARK: History

    @ViewBuilder
    private func history(_ meds: [Med], now: Date) -> some View {
        let today = DayKey(now, calendar: context.calendar)
        let days = (1...14).map { today.adding(days: -$0, calendar: context.calendar) }
            .filter { !MedPlan.slots(meds, on: $0, calendar: context.calendar).isEmpty }
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                WidgetUI.header("Past two weeks", theme: theme)
                ForEach(days, id: \.self) { day in
                    let slots = MedPlan.slots(meds, on: day, calendar: context.calendar)
                    HStack {
                        Text(day.date(calendar: context.calendar).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).frame(width: 96, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(slots) { slot in
                                Circle().fill(MedColors.color(MedPlan.state(slot, doses: doses, now: now), theme: theme, accent: context.accent))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        Spacer()
                        let taken = slots.filter { MedPlan.state($0, doses: doses, now: now) == .taken }.count
                        Text("\(taken)/\(slots.count)").font(.system(size: 13, design: .rounded)).foregroundStyle(theme.label)
                    }
                }
            }
        }
    }

    // MARK: Edits

    private func save(_ med: Med) {
        settings.update { s in
            if let i = s.meds.firstIndex(where: { $0.id == med.id }) { s.meds[i] = med } else { s.meds.append(med) }
        }
        context.track("med_saved", ["times": "\(med.times.count)"])
        Task { notificationsOff = !(await MedReminderScheduler.sync(settings.model)) }
    }

    private func delete(_ med: Med) {
        settings.update { $0.meds.removeAll { $0.id == med.id } }
        Task { await MedReminderScheduler.sync(settings.model) }
    }
}

enum MedSchedule {
    static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    /// "8:00 AM, 8:00 PM · every day" / "9:00 AM · Mon, Thu"
    static func summary(_ med: Med, calendar: Calendar) -> String {
        let times = med.times.map { MedPlan.timeText($0, calendar: calendar) }.joined(separator: ", ")
        let names = calendar.shortWeekdaySymbols
        let days = med.days.isEmpty ? "every day" : med.days.map { names[($0 - 1) % 7] }.joined(separator: ", ")
        return "\(times) · \(days)\(med.active ? "" : " · paused")"
    }
}

/// Add or edit one medication.
struct MedEditSheet: View {
    let context: WidgetContext
    let med: Med?
    let onSave: (Med) -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dose = ""
    @State private var note = ""
    @State private var times: [Date] = []
    @State private var days: Set<Int> = []
    @State private var active = true

    init(context: WidgetContext, med: Med?, onSave: @escaping (Med) -> Void, onDelete: (() -> Void)?) {
        self.context = context; self.med = med; self.onSave = onSave; self.onDelete = onDelete
        let cal = context.calendar
        _name = State(initialValue: med?.name ?? "")
        _dose = State(initialValue: med?.dose ?? "")
        _note = State(initialValue: med?.note ?? "")
        _days = State(initialValue: Set(med?.days ?? []))
        _active = State(initialValue: med?.active ?? true)
        _times = State(initialValue: (med?.times ?? [8 * 60]).map { m in
            cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        })
    }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: med == nil ? "Add medication" : "Edit medication", theme: theme,
                    confirm: ("Save", !name.trimmingCharacters(in: .whitespaces).isEmpty && !times.isEmpty, save)) {
            Form {
                Section {
                    TextField("Name (e.g. Lisinopril)", text: $name)
                    TextField("Dose (e.g. 10 mg)", text: $dose)
                    TextField("Note (e.g. with food)", text: $note)
                }
                Section("Times") {
                    ForEach(times.indices, id: \.self) { i in
                        HStack {
                            DatePicker("Dose \(i + 1)", selection: $times[i], displayedComponents: .hourAndMinute)
                            if times.count > 1 {
                                Button { times.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(theme.danger) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if times.count < 6 {
                        Button("Add a time") {
                            times.append(context.calendar.date(byAdding: .hour, value: 12, to: times.last ?? Date()) ?? Date())
                        }
                    }
                }
                Section {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = days.isEmpty || days.contains(d)
                            Button { toggle(d) } label: {
                                Text(MedSchedule.dayLetters[d - 1]).font(.system(size: 14, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(on ? context.accent : theme.tertiaryBackground))
                                    .foregroundStyle(on ? .white : theme.label)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("Days") } footer: { Text(days.isEmpty ? "Every day" : "Only on the days shown") }
                if med != nil {
                    Section {
                        Toggle("Reminders on", isOn: $active)
                        if let onDelete {
                            Button("Delete medication", role: .destructive) { onDelete(); dismiss() }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ d: Int) {
        var set = days.isEmpty ? Set(1...7) : days
        if set.contains(d) { set.remove(d) } else { set.insert(d) }
        days = set.count == 7 || set.isEmpty ? [] : set
    }

    private func save() {
        let cal = context.calendar
        let minutes = Array(Set(times.map { cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0) })).sorted()
        var result = med ?? Med(name: "")
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.dose = dose.trimmingCharacters(in: .whitespaces)
        result.note = note.trimmingCharacters(in: .whitespaces)
        result.times = minutes
        result.days = days.sorted()
        result.active = active
        onSave(result)
        dismiss()
    }
}

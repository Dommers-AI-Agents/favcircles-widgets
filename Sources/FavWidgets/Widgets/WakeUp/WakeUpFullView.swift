import SwiftUI
import FavWidgetsCore

/// The alarms, the stations they open, and a "ring in a minute" to try it.
struct WakeUpFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<AlarmClockSettings>
    @State private var permission: WidgetAlarmPermission = .notDetermined
    @State private var syncError: String?
    @State private var editingAlarm: WakeAlarm?
    @State private var addingAlarm = false
    @State private var editingStation: MusicStation?
    @State private var addingStation = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                permissionBanner
                if let syncError {
                    Label(syncError, systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(theme.danger)
                }
                nextUp
                alarmList
                stationList
                tryIt
                Text("Alarms ring even on silent or in a Focus. Stop opens your station; Snooze rings again after the minutes you pick. Private to you.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .task {
            await settings.loadIfNeeded()
            permission = await context.host.alarmPermission()
            syncError = await WakeUpSync.sync(settings, context: context)
        }
        .sheet(item: $editingAlarm) { alarm in
            WakeAlarmEditSheet(context: context, alarm: alarm, stations: settings.model.stations,
                               onSave: { save($0) }, onDelete: { delete(alarm) }, onAddStation: addStationAfterSheet)
        }
        .sheet(isPresented: $addingAlarm) {
            WakeAlarmEditSheet(context: context, alarm: nil, stations: settings.model.stations,
                               onSave: { save($0) }, onDelete: nil, onAddStation: addStationAfterSheet)
        }
        .sheet(item: $editingStation) { station in
            MusicStationEditSheet(context: context, station: station, onSave: { saveStation($0) }, onDelete: { deleteStation(station) })
        }
        .sheet(isPresented: $addingStation) {
            MusicStationEditSheet(context: context, station: nil, onSave: { saveStation($0) }, onDelete: nil)
        }
    }

    /// From the alarm sheet: once it has closed, open the station sheet
    private func addStationAfterSheet() {
        Task { @MainActor in
            await context.waitForPageToSettle()
            addingStation = true
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionBanner: some View {
        switch permission {
        case .unavailable:
            banner("Wake Up needs iOS 26 or later", "Update your iPhone in Settings → General → Software Update to use alarms.", button: nil)
        case .denied:
            banner("Alarms are off for FavCircles", "Turn on Alarms for FavCircles in iPhone Settings so they can ring.",
                   button: ("Open Settings", { context.host.openNotificationSettings() }))
        case .notDetermined, .allowed:
            EmptyView()
        }
    }

    private func banner(_ title: String, _ detail: String, button: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "alarm.waves.left.and.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            Text(detail).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            if let button {
                Button(button.0, action: button.1).font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private var canRing: Bool { permission != .unavailable }

    // MARK: Next

    @ViewBuilder
    private var nextUp: some View {
        if let next = AlarmClockPlan.next(settings.model.alarms, after: Date(), calendar: context.calendar) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AlarmClockPlan.ringsIn(next.at, from: Date())).font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.label)
                if let station = settings.model.station(id: next.alarm.stationId) {
                    Label("Then \(station.name) on \(station.service.name)", systemImage: station.service.symbolName)
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                }
            }
        }
    }

    // MARK: Alarms

    private var alarmList: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Alarms", theme: theme)
            if settings.model.alarms.isEmpty {
                Text("No alarms yet.").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(settings.model.alarms.sorted { $0.minutes < $1.minutes }) { alarm in
                alarmRow(alarm)
            }
            WidgetUI.primaryButton("Add an alarm", color: context.accent) { addingAlarm = true }
                .disabled(!canRing).opacity(canRing ? 1 : 0.4)
        }
    }

    private func alarmRow(_ alarm: WakeAlarm) -> some View {
        let station = settings.model.station(id: alarm.stationId)
        let detail = [AlarmClockPlan.daysText(alarm.days, calendar: context.calendar),
                      alarm.label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : alarm.label,
                      station?.name].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Button { editingAlarm = alarm } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlarmClockPlan.timeText(alarm.minutes, calendar: context.calendar))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(alarm.enabled ? theme.label : theme.secondaryLabel)
                    Text(detail).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { on in
                var next = alarm
                next.enabled = on
                save(next)
            }))
            .labelsHidden()
            .tint(context.accent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    // MARK: Stations

    private var stationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Stations", theme: theme)
            Text("In Pandora, Spotify or Apple Music, open a station or playlist, tap Share, then Copy Link, and add it here.")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            ForEach(settings.model.stations) { station in
                Button { editingStation = station } label: {
                    HStack(spacing: 10) {
                        Image(systemName: station.service.symbolName).foregroundStyle(context.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(station.name).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label)
                            Text(station.service.name).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { addingStation = true } label: {
                Label("Add a station", systemImage: "plus.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Try it

    @ViewBuilder
    private var tryIt: some View {
        if canRing {
            Button { ringSoon() } label: {
                Label("Try it: ring in a minute", systemImage: "alarm").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// A one-time "Test alarm" a minute or two from now, on the first
    /// station; it switches itself off after it rings.
    private func ringSoon() {
        let cal = context.calendar
        let now = Date()
        let at = cal.date(byAdding: .minute, value: cal.component(.second, from: now) < 40 ? 1 : 2, to: now) ?? now
        let alarm = WakeAlarm(minutes: cal.component(.hour, from: at) * 60 + cal.component(.minute, from: at),
                              label: "Test alarm", stationId: settings.model.stations.first?.id)
        save(alarm)
        context.track("wakeup_test_alarm")
    }

    // MARK: Edits

    private func save(_ alarm: WakeAlarm) {
        var alarm = alarm
        // A one-time alarm remembers when it rings so it can switch itself off after
        alarm.onceAt = alarm.enabled && !alarm.repeats
            ? AlarmClockPlan.nextRing(alarm, after: Date(), calendar: context.calendar) : nil
        settings.update { s in
            if let i = s.alarms.firstIndex(where: { $0.id == alarm.id }) { s.alarms[i] = alarm } else { s.alarms.append(alarm) }
        }
        context.track("wakeup_alarm_saved", ["repeats": alarm.repeats ? "1" : "0", "station": alarm.stationId == nil ? "0" : "1"])
        Task { @MainActor in
            if alarm.enabled, permission == .notDetermined {
                _ = await context.host.requestAlarmPermission()
                permission = await context.host.alarmPermission()
            }
            syncError = await WakeUpSync.sync(settings, context: context)
        }
    }

    private func delete(_ alarm: WakeAlarm) {
        settings.update { $0.alarms.removeAll { $0.id == alarm.id } }
        Task { syncError = await WakeUpSync.sync(settings, context: context) }
    }

    private func saveStation(_ station: MusicStation) {
        settings.update { s in
            if let i = s.stations.firstIndex(where: { $0.id == station.id }) { s.stations[i] = station } else { s.stations.append(station) }
        }
        context.track("wakeup_station_saved", ["service": station.service.rawValue])
        Task { syncError = await WakeUpSync.sync(settings, context: context) }
    }

    private func deleteStation(_ station: MusicStation) {
        settings.update { s in
            s.stations.removeAll { $0.id == station.id }
            for i in s.alarms.indices where s.alarms[i].stationId == station.id { s.alarms[i].stationId = nil }
        }
        Task { syncError = await WakeUpSync.sync(settings, context: context) }
    }
}

/// Add or edit one alarm.
struct WakeAlarmEditSheet: View {
    let context: WidgetContext
    let alarm: WakeAlarm?
    let stations: [MusicStation]
    let onSave: (WakeAlarm) -> Void
    let onDelete: (() -> Void)?
    let onAddStation: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var days: Set<Int>
    @State private var label: String
    @State private var stationId: String?
    @State private var snooze: Int

    init(context: WidgetContext, alarm: WakeAlarm?, stations: [MusicStation], onSave: @escaping (WakeAlarm) -> Void,
         onDelete: (() -> Void)?, onAddStation: @escaping () -> Void) {
        self.context = context; self.alarm = alarm; self.stations = stations
        self.onSave = onSave; self.onDelete = onDelete; self.onAddStation = onAddStation
        let minutes = alarm?.minutes ?? 7 * 60
        _time = State(initialValue: context.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date())
        _days = State(initialValue: Set(alarm?.days ?? []))
        _label = State(initialValue: alarm?.label ?? "")
        _stationId = State(initialValue: alarm?.stationId ?? (alarm == nil ? stations.first?.id : nil))
        _snooze = State(initialValue: alarm?.snoozeMinutes ?? AlarmClockPlan.defaultSnooze)
    }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: alarm == nil ? "Add alarm" : "Edit alarm", theme: theme, confirm: ("Save", true, save)) {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        #if os(iOS)
                        .datePickerStyle(.wheel)
                        #endif
                        .labelsHidden().frame(maxWidth: .infinity)
                }
                Section {
                    HStack(spacing: 6) {
                        // Monday first
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                            let on = days.contains(d)
                            Button { if on { days.remove(d) } else { days.insert(d) } } label: {
                                Text(MedSchedule.dayLetters[d - 1]).font(.system(size: 14, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(on ? context.accent : theme.tertiaryBackground))
                                    .foregroundStyle(on ? .white : theme.label)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("Repeat") } footer: {
                    Text(days.isEmpty ? "Rings once" : AlarmClockPlan.daysText(Array(days), calendar: context.calendar))
                }
                Section("Wake up to") {
                    Picker("Station", selection: $stationId) {
                        Text("No station").tag(String?.none)
                        ForEach(stations) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    Button("Add a station") { dismiss(); onAddStation() }
                }
                Section {
                    TextField("Label (e.g. Gym)", text: $label)
                    Picker("Snooze", selection: $snooze) {
                        ForEach(AlarmClockPlan.snoozeChoices, id: \.self) { m in
                            Text(m == 0 ? "Off" : "\(m) minutes").tag(m)
                        }
                    }
                }
                if let onDelete {
                    Section {
                        Button("Delete alarm", role: .destructive) { onDelete(); dismiss() }
                    }
                }
            }
        }
    }

    private func save() {
        let cal = context.calendar
        var result = alarm ?? WakeAlarm()
        result.minutes = cal.component(.hour, from: time) * 60 + cal.component(.minute, from: time)
        result.days = days.sorted()
        result.label = label.trimmingCharacters(in: .whitespaces)
        result.stationId = stationId
        result.snoozeMinutes = snooze
        result.enabled = true
        onSave(result)
        dismiss()
    }
}

/// Add or edit one station: a name and the link from the music app's Share.
struct MusicStationEditSheet: View {
    let context: WidgetContext
    let station: MusicStation?
    let onSave: (MusicStation) -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var link: String

    init(context: WidgetContext, station: MusicStation?, onSave: @escaping (MusicStation) -> Void, onDelete: (() -> Void)?) {
        self.context = context; self.station = station; self.onSave = onSave; self.onDelete = onDelete
        _name = State(initialValue: station?.name ?? "")
        _link = State(initialValue: station?.link ?? "")
    }

    private var url: URL? { MusicLink.url(from: link) }
    private var canSave: Bool { url != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: station == nil ? "Add station" : "Edit station", theme: theme, confirm: ("Save", canSave, save)) {
            Form {
                Section {
                    TextField("Name (e.g. Morning Mix)", text: $name)
                    #if os(iOS)
                    TextField("Link", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button {
                        if let text = UIPasteboard.general.string { link = text }
                    } label: { Label("Paste link", systemImage: "doc.on.clipboard") }
                    #else
                    TextField("Link", text: $link, axis: .vertical)
                    #endif
                } footer: {
                    if link.isEmpty {
                        Text("In the music app, open the station, tap Share, then Copy Link.")
                    } else if let url {
                        Text("Opens in \(MusicLink.service(of: link).name): \(url.absoluteString)")
                    } else {
                        Text("That doesn't look like a link.").foregroundStyle(theme.danger)
                    }
                }
                if let url {
                    Section {
                        Button("Try the link") { context.host.openURL(url) }
                    } footer: { Text("Check it opens the right station before you rely on it.") }
                }
                if let onDelete {
                    Section {
                        Button("Delete station", role: .destructive) { onDelete(); dismiss() }
                    }
                }
            }
        }
    }

    private func save() {
        var result = station ?? MusicStation(name: "", link: "")
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.link = url?.absoluteString ?? link
        onSave(result)
        dismiss()
    }
}

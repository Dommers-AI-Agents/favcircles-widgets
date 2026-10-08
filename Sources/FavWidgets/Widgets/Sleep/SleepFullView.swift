import SwiftUI
import FavWidgetsCore

struct SleepFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<SleepSettings>
    @ObservedObject var month: WidgetStateController<SleepMonth>
    @ObservedObject var previous: WidgetStateController<SleepMonth>
    @State private var logging = false
    @State private var refreshing = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        let nights = SleepData.nights(month, previous)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let last = nights.last { lastNight(last, nights: nights) } else { empty }
                if nights.count > 1 { chart(Array(nights.suffix(14))) }
                averages(nights)
                healthRow
                WidgetUI.primaryButton(nights.last?.day == DayKey(Date(), calendar: context.calendar) ? "Edit last night" : "Log last night",
                                       color: context.accent) { logging = true }
                goalRow
                Text("Read from Apple Health on this phone; nothing is written to Health. Your nights are private to you.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .refreshable { await SleepData.refreshFromHealth(context: context, settings: settings) }
        .task {
            await settings.loadIfNeeded(); await month.loadIfNeeded(); await previous.loadIfNeeded()
            await SleepData.refreshFromHealth(context: context, settings: settings)
        }
        .sheet(isPresented: $logging) {
            SleepLogSheet(context: context, existing: nights.last.flatMap { $0.day == DayKey(Date(), calendar: context.calendar) ? $0 : nil }) { night in
                let shard = context.month(SleepMonth.self, night.day.monthKey)
                Task { await shard.loadIfNeeded(); shard.update { $0.upsert(night) } }
                context.track("sleep_logged")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 40)).foregroundStyle(context.accent)
            Text("Your sleep score shows here").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
            Text("Connect Apple Health (iPhone or Watch sleep tracking), or log last night yourself.")
                .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func lastNight(_ night: SleepNight, nights: [SleepNight]) -> some View {
        let recent = SleepData.recentBedtimes(before: night, in: nights)
        let s = SleepScore.score(night, goalHours: settings.model.goalHours, recentBedtimes: recent, calendar: context.calendar)
        return VStack(spacing: 10) {
            SleepRing(score: s.total, accent: context.accent, theme: theme)
            Text("\(SleepScore.label(s.total)) · \(SleepScore.durationText(night.asleepMinutes)) asleep")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
            Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wakeTime.formatted(date: .omitted, time: .shortened))\(night.source == .manual ? " · logged" : "")")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            if let note = SleepScore.bedtimeNote(night, recentBedtimes: recent, calendar: context.calendar) {
                Text(note).font(.system(size: 13)).foregroundStyle(theme.warning)
            }
            HStack(spacing: 8) {
                part("Duration", s.duration, of: 50)
                part("Restful", s.efficiency, of: 20)
                part("On schedule", s.consistency, of: 20)
                if let st = s.stages { part("Deep + REM", st, of: 10) }
            }
            if night.hasStages { stages(night) }
        }
        .frame(maxWidth: .infinity)
    }

    private func part(_ title: String, _ value: Int, of max: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)/\(max)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondaryLabel).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
    }

    private func stages(_ n: SleepNight) -> some View {
        let parts: [(String, Int, Color)] = [("Deep", n.deepMinutes ?? 0, .indigo), ("REM", n.remMinutes ?? 0, .cyan),
                                             ("Core", n.coreMinutes ?? 0, .blue), ("Awake", n.awakeMinutes, .orange)]
        let total = max(1, parts.map(\.1).reduce(0, +))
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { p in
                        RoundedRectangle(cornerRadius: 3).fill(p.2)
                            .frame(width: max(0, geo.size.width * CGFloat(p.1) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 10) {
                ForEach(parts, id: \.0) { p in
                    Label("\(p.0) \(SleepScore.durationText(p.1))", systemImage: "circle.fill")
                        .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel).labelStyle(SleepDotLabel(color: p.2))
                }
            }
        }
    }

    private func chart(_ nights: [SleepNight]) -> some View {
        let goal = settings.model.goalHours * 60
        let maxM = max(goal + 60, Double(nights.map(\.asleepMinutes).max() ?? 0))
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Last \(nights.count) nights", theme: theme)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(nights) { n in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Double(n.asleepMinutes) >= goal - 30 ? context.accent : context.accent.opacity(0.45))
                            .frame(height: max(4, 110 * CGFloat(Double(n.asleepMinutes) / maxM)))
                        Text(n.day.date(calendar: context.calendar).formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func averages(_ nights: [SleepNight]) -> some View {
        let week = SleepScore.averageMinutes(Array(nights.suffix(7)))
        let monthAvg = SleepScore.averageMinutes(Array(nights.suffix(30)))
        if week != nil {
            HStack(spacing: 12) {
                avg("7-night average", week)
                avg("30-night average", monthAvg)
            }
        }
    }

    private func avg(_ title: String, _ minutes: Int?) -> some View {
        VStack(spacing: 4) {
            Text(minutes.map(SleepScore.durationText) ?? "—").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    @ViewBuilder
    private var healthRow: some View {
        if SleepHealthReader.isAvailable {
            Button {
                Task {
                    refreshing = true
                    if await SleepHealthReader.requestAccess() {
                        settings.update { $0.healthConnected = true }
                        await SleepData.refreshFromHealth(context: context, settings: settings)
                        context.track("sleep_health_connected")
                    }
                    refreshing = false
                }
            } label: {
                HStack {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(.pink)
                    Text(settings.model.healthConnected ? "Apple Health connected · Refresh" : "Connect Apple Health")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    Spacer()
                    if refreshing { ProgressView() }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
            }
            .buttonStyle(.plain)
        }
    }

    private var goalRow: some View {
        Stepper(value: Binding(get: { settings.model.goalHours }, set: { v in settings.update { $0.goalHours = v } }),
                in: 5...10, step: 0.5) {
            Text("Sleep goal: \(settings.model.goalHours.formatted(.number.precision(.fractionLength(0...1)))) hours")
                .font(.system(size: 15)).foregroundStyle(theme.label)
        }
    }
}

struct SleepDotLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { Circle().fill(color).frame(width: 6, height: 6); configuration.title }
    }
}

/// "Log last night": when you went to bed and got up, and how it felt.
struct SleepLogSheet: View {
    let context: WidgetContext
    let existing: SleepNight?
    let onSave: (SleepNight) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var bedtime: Date
    @State private var wake: Date
    @State private var feeling: Int

    init(context: WidgetContext, existing: SleepNight?, onSave: @escaping (SleepNight) -> Void) {
        self.context = context; self.existing = existing; self.onSave = onSave
        let cal = context.calendar
        let today = Date()
        let defaultBed = cal.date(bySettingHour: 23, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: today) ?? today) ?? today
        let defaultWake = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today) ?? today
        _bedtime = State(initialValue: existing?.bedtime ?? defaultBed)
        _wake = State(initialValue: existing?.wakeTime ?? defaultWake)
        _feeling = State(initialValue: existing?.feeling ?? 3)
    }

    var body: some View {
        WidgetSheet(title: "Last night", theme: context.theme, confirm: ("Save", wake > bedtime, save)) {
            Form {
                DatePicker("Went to bed", selection: $bedtime)
                DatePicker("Got up", selection: $wake)
                Section("How did you sleep?") {
                    Picker("Feeling", selection: $feeling) {
                        Text("😫").tag(1); Text("😕").tag(2); Text("😐").tag(3); Text("🙂").tag(4); Text("😴").tag(5)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func save() {
        let minutes = Int(wake.timeIntervalSince(bedtime) / 60)
        // Feeling nudges "asleep" a little: rough nights rarely mean every minute in bed was sleep
        let asleep = Int(Double(minutes) * [0.8, 0.85, 0.9, 0.93, 0.96][max(0, min(feeling, 5) - 1)])
        onSave(SleepNight(day: DayKey(wake, calendar: context.calendar), bedtime: bedtime, wakeTime: wake,
                          asleepMinutes: asleep, awakeMinutes: max(0, minutes - asleep), source: .manual, feeling: feeling))
        dismiss()
    }
}

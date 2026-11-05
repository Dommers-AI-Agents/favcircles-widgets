import SwiftUI
import FavWidgetsCore

/// Bedtime (Wes, 2026-11-05): a time, the days, which sound. At that time a
/// reminder with a Play button; "Make it fully automatic" shows how to have
/// the Shortcuts app start it with no tap (iOS won't let an app start sound
/// by itself).
struct SleepBedtimeSection: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<SleepSoundsSettings>
    @State private var notificationsOff = false
    @State private var showAutomatic = false

    private var theme: WidgetTheme { context.theme }
    private var bedtime: SleepBedtime { settings.model.bedtime ?? SleepBedtime() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Bedtime", theme: theme)
            Toggle(isOn: Binding(get: { bedtime.enabled }, set: { on in change { $0.enabled = on } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start sleep sounds at bedtime").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                    Text(bedtime.enabled ? summary : "A reminder with a Play button, on the nights you choose")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(context.accent)

            if bedtime.enabled {
                DatePicker("Time", selection: Binding(get: { timeDate }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    change { $0.minutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 0) }
                }), displayedComponents: .hourAndMinute)
                    .font(.system(size: 15)).foregroundStyle(theme.label)

                dayChips

                HStack {
                    Text("Sound").font(.system(size: 15)).foregroundStyle(theme.label)
                    Spacer()
                    Menu {
                        Button("Whatever played last") { change { $0.mixId = nil } }
                        ForEach(settings.model.mixes + SleepMix.builtIns) { mix in
                            Button(mix.name) { change { $0.mixId = mix.id } }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(soundName).font(.system(size: 15, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                        }
                        .foregroundStyle(context.accent)
                    }
                }

                if notificationsOff {
                    Button { context.host.openNotificationSettings() } label: {
                        Label("Notifications are off for FavCircles. Turn them on to get the bedtime reminder.", systemImage: "bell.slash")
                            .font(.system(size: 13)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }

                Button { showAutomatic = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars").font(.system(size: 18)).foregroundStyle(context.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Make it fully automatic").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            Text("Start with no tap, using the Shortcuts app").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showAutomatic) { SleepAutomaticGuide(context: context, bedtime: bedtime) }
    }

    private var summary: String {
        "\(SleepBedtimeCopy.time(bedtime.minutes)) · \(SleepBedtimePlan.daysLabel(bedtime.weekdays)) · \(soundName)"
    }

    private var soundName: String {
        guard let id = bedtime.mixId else { return "Last played" }
        return (settings.model.mixes + SleepMix.builtIns).first { $0.id == id }?.name ?? "Last played"
    }

    private var timeDate: Date {
        Calendar.current.date(bySettingHour: bedtime.minutes / 60, minute: bedtime.minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private var dayChips: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = bedtime.weekdays.contains(day)
                Button {
                    change { b in
                        if on { b.weekdays.removeAll { $0 == day } } else { b.weekdays = (b.weekdays + [day]).sorted() }
                    }
                } label: {
                    Text(symbols[day - 1])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? .white : theme.label)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Circle().fill(on ? context.accent : theme.secondaryBackground))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// Saves the change, then re-plans this phone's reminders
    private func change(_ edit: (inout SleepBedtime) -> Void) {
        var next = bedtime
        edit(&next)
        settings.update { $0.bedtime = next }
        context.host.haptic(.selection)
        context.track("sleepsounds_bedtime", ["enabled": next.enabled ? "1" : "0", "days": "\(next.weekdays.count)"])
        let model = settings.model
        Task {
            let allowed = await SleepSoundsBedtime.sync(model)
            await MainActor.run { notificationsOff = next.enabled && !allowed }
        }
    }
}

/// How to have Shortcuts start Sleep Sounds at bedtime with no tap
struct SleepAutomaticGuide: View {
    let context: WidgetContext
    let bedtime: SleepBedtime

    var body: some View {
        WidgetSheet(title: "Fully automatic", theme: context.theme) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("iPhone doesn't let apps start sound by themselves, but the Shortcuts app can, every night, with no tap. It takes about 30 seconds to set up once:")
                        .font(.system(size: 15)).foregroundStyle(context.theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(SleepBedtimeCopy.steps(bedtime).enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(context.accent))
                            Text(step).font(.system(size: 15)).foregroundStyle(context.theme.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    WidgetUI.primaryButton("Open Shortcuts", color: context.accent) {
                        context.track("sleepsounds_open_shortcuts")
                        if let url = URL(string: "shortcuts://") { context.host.openURL(url) }
                    }
                    Text("The bedtime reminder still comes as a backup. Turn it off here if you'd rather only use the automation.")
                        .font(.system(size: 12)).foregroundStyle(context.theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
    }
}

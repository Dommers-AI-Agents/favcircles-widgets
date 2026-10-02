import SwiftUI
import FavWidgetsCore

/// Full screen: the coach shouting this hour's line ("Hit me again" for
/// another), "Did it" with a streak, and settings — how hard he goes, what
/// about, and when he reminds you.
struct MotivationFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<MotivationLog>

    @State private var extra = 0
    @State private var reminderError: String?
    /// A line opened from a notification or a friend's chat card: the coach
    /// shows it until "Hit me again".
    @State private var pinnedLine: String?
    /// The line being sent (drives the send sheet).
    @State private var sending: SendTarget?

    private struct SendTarget: Identifiable {
        let line: String
        let source: String
        var id: String { line }
    }

    private var shownLine: String { pinnedLine ?? state.model.currentLine(extra: extra) }

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WidgetSyncBadge(state: state.syncState, theme: theme)
                coachSection(theme: theme)
                styleSection(theme: theme)
                remindersSection(theme: theme)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await state.loadIfNeeded() }
        .task { await openLaunchedLine() }
        .sheet(item: $sending) { target in
            MotivationSendSheet(context: context, line: target.line, source: target.source)
        }
    }

    /// From a notification's "Send to someone" (open the send sheet) or a
    /// friend's chat card (just show the line). Not until the push lands.
    private func openLaunchedLine() async {
        guard let id = context.launchMotivationLineId else { return }
        let send = context.launchMotivationSend
        context.launchMotivationLineId = nil
        context.launchMotivationSend = false
        guard let line = MotivationLines.line(id: id) else { return }
        pinnedLine = line
        context.track("motivation_line_opened", ["action": send ? "send" : "show"])
        guard send else { return }
        await context.waitForPageToSettle()
        sending = SendTarget(line: line, source: "push")
    }

    // MARK: - Coach

    @ViewBuilder
    private func coachSection(theme: WidgetTheme) -> some View {
        let model = state.model
        let today = context.today
        let done = model.isDone(today)
        let streak = model.streak(endingOn: today, calendar: context.calendar)

        VStack(spacing: 14) {
            CoachShoutView(line: shownLine, size: 150, accent: context.accent, theme: theme)
                .onTapGesture { hitMeAgain() }

            HStack(spacing: 10) {
                Button { hitMeAgain() } label: {
                    Label("Hit me again", systemImage: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.tertiaryBackground))
                        .foregroundStyle(theme.label)
                }
                .buttonStyle(.plain)
                Button { setDone(!done) } label: {
                    Label(done ? "Done today" : "Did it", systemImage: done ? "checkmark.circle.fill" : "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(done ? theme.tertiaryBackground : context.accent))
                        .foregroundStyle(done ? context.accent : .white)
                }
                .buttonStyle(.plain)
                .accessibilityHint(done ? "Tap to undo" : "Marks today done and quiets today's reminders")
            }

            Button { sending = SendTarget(line: shownLine, source: "page") } label: {
                Label("Send to someone who needs it", systemImage: "megaphone.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(context.accent, lineWidth: 1.5))
                    .foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? theme.warning : theme.secondaryLabel)
                Text(streakText(streak: streak, done: done))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.label)
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
    }

    private func streakText(streak: Int, done: Bool) -> String {
        if done { return streak == 1 ? "Done today · 1-day streak" : "Done today · \(streak)-day streak" }
        if streak == 0 { return "Go do it, then tap Did it" }
        return "\(streak)-day streak — don't you dare break it"
    }

    private func hitMeAgain() {
        pinnedLine = nil
        extra += 1
        context.host.haptic(.medium)
        context.track("motivation_hit_me_again")
    }

    private func setDone(_ done: Bool) {
        let today = context.today
        state.update { $0.setDone(done, on: today) }
        context.host.haptic(done ? .success : .light)
        context.track("motivation_did_it", ["on": done ? "1" : "0"])
        resync()
    }

    // MARK: - Style

    @ViewBuilder
    private func styleSection(theme: WidgetTheme) -> some View {
        let model = state.model
        VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("How hard", theme: theme)
            Picker("Intensity", selection: Binding(
                get: { state.model.intensity },
                set: { value in
                    state.update { $0.intensity = value }
                    context.track("motivation_intensity", ["value": value.rawValue])
                    extra = 0
                    pinnedLine = nil
                    resync()
                }
            )) {
                ForEach(MotivationIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(model.intensity == .savage
                 ? "Savage doesn't hold back. No swearing — just no sympathy either."
                 : "Blunt and encouraging. Switch to Savage if you want it rougher.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            WidgetUI.header("Yell at me about", theme: theme)
            HStack(spacing: 8) {
                ForEach(MotivationFocus.allCases, id: \.self) { focus in
                    let on = model.focus.contains(focus)
                    Button { toggle(focus) } label: {
                        Text(focus.title)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(on ? context.accent : theme.tertiaryBackground))
                            .foregroundStyle(on ? .white : theme.label)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func toggle(_ focus: MotivationFocus) {
        state.update { log in
            if let i = log.focus.firstIndex(of: focus) {
                // Keep at least one, or the coach has nothing to say.
                if log.focus.count > 1 { log.focus.remove(at: i) }
            } else {
                log.focus.append(focus)
            }
        }
        extra = 0
        pinnedLine = nil
        resync()
    }

    // MARK: - Reminders

    @ViewBuilder
    private func remindersSection(theme: WidgetTheme) -> some View {
        let reminders = state.model.reminders
        VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Reminders", theme: theme)
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { state.model.reminders.enabled },
                    set: { on in
                        state.update { $0.reminders.enabled = on }
                        context.track("motivation_reminders_toggled", ["on": on ? "1" : "0"])
                        resync()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coach notifications").foregroundStyle(theme.label)
                        Text(WaterReminderPlan.summary(reminders, quietHours: context.host.quietHours))
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
                .padding(.vertical, 10)
                if reminders.enabled {
                    Divider().overlay(theme.separator)
                    HStack {
                        Text("Every").foregroundStyle(theme.label)
                        Spacer()
                        Picker("Interval", selection: Binding(
                            get: { state.model.reminders.intervalHours },
                            set: { hours in state.update { $0.reminders.intervalHours = hours }; resync() }
                        )) {
                            ForEach(WaterReminders.intervalChoices, id: \.self) { h in Text(h == 1 ? "hour" : "\(h) hours").tag(h) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }
                    .padding(.vertical, 10)
                    Divider().overlay(theme.separator)
                    timeRow("From", minutes: Binding(
                        get: { state.model.reminders.startMinutes },
                        set: { m in state.update { $0.reminders.startMinutes = m; if $0.reminders.endMinutes < m { $0.reminders.endMinutes = m } }; resync() }
                    ), theme: theme)
                    Divider().overlay(theme.separator)
                    timeRow("Until", minutes: Binding(
                        get: { state.model.reminders.endMinutes },
                        set: { m in state.update { $0.reminders.endMinutes = max(m, $0.reminders.startMinutes) }; resync() }
                    ), theme: theme)
                }
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
            if let reminderError {
                Text(reminderError).font(.system(size: 12)).foregroundStyle(theme.warning)
            } else if reminders.enabled {
                Text(reminderFootnote)
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: state.hasLoaded) {
            // Tops up the rolling schedule, and picks it up on a second phone.
            if state.hasLoaded, state.model.reminders.enabled { resync() }
        }
    }

    private func timeRow(_ title: String, minutes: Binding<Int>, theme: WidgetTheme) -> some View {
        HStack {
            Text(title).foregroundStyle(theme.label)
            Spacer()
            DatePicker("", selection: Binding(
                get: {
                    var comps = DateComponents(); comps.hour = minutes.wrappedValue / 60; comps.minute = minutes.wrappedValue % 60
                    return Calendar.current.date(from: comps) ?? Date()
                },
                set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .tint(context.accent)
        }
        .padding(.vertical, 6)
    }

    private var reminderFootnote: String {
        var text = "Push notifications on this phone, a different line each time. Tap Did it (or press and hold a notification) and he leaves you alone until tomorrow."
        if let quiet = context.host.quietHours {
            text += " None during your quiet hours (\(WaterReminderPlan.clock(quiet.startMinutes)) – \(WaterReminderPlan.clock(quiet.endMinutes)))."
        }
        return text
    }

    private func resync() {
        let log = state.model
        let quiet = context.host.quietHours
        Task {
            let ok = await MotivationReminderScheduler.sync(log, quietHours: quiet)
            reminderError = ok ? nil : "Notifications are off for Circles. Turn them on in Settings to hear from the coach."
        }
    }
}

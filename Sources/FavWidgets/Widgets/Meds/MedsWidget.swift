import SwiftUI
import FavWidgetsCore

/// Medication reminders (Wes, 2026-10-08): a reminder at each dose time,
/// "Took it" right from the notification, today's checklist and how
/// consistently you've taken them. Private to the person.
public struct MedsWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: MedQuickLog.widgetId,
        title: "Medications",
        subtitle: "Reminders for every dose",
        symbolName: "pills.fill",
        accentHex: "#38A169",
        category: .health,
        storage: .monthly,
        schemaVersion: MedSettings.schemaVersion,
        shareBlurb: "Never miss a dose: a reminder at each time, and Took it right from the notification."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(MedsCardView(context: context, settings: context.state(MedSettings.self),
                             month: context.month(MedMonth.self, context.currentMonth)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(MedsFullView(context: context, settings: context.state(MedSettings.self),
                             month: context.month(MedMonth.self, context.currentMonth),
                             previous: context.month(MedMonth.self, context.currentMonth.previous)))
    }
}

/// Marks a dose in the month it belongs to (an evening dose after midnight
/// on the 1st still belongs to last month's last day).
@MainActor
enum MedLogging {
    static func mark(_ slot: MedPlan.Slot, _ status: MedDoseStatus?, context: WidgetContext) {
        let shard = context.month(MedMonth.self, slot.day.monthKey)
        Task { @MainActor in
            await shard.loadIfNeeded()
            shard.update { month in
                if let status {
                    month.record(MedDose(medId: slot.med.id, day: slot.day, slot: slot.minutes, status: status, at: Date()))
                } else {
                    month.remove(id: slot.id)
                }
            }
            context.host.haptic(status == .taken ? .success : .light)
            context.track("med_marked", ["status": status?.rawValue ?? "undo"])
        }
    }
}

struct MedsCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<MedSettings>
    @ObservedObject var month: WidgetStateController<MedMonth>

    var body: some View {
        let theme = context.theme
        let now = Date()
        let meds = settings.model.activeMeds
        let next = MedPlan.next(meds, doses: month.model.doses, now: now, calendar: context.calendar)
        let isToday = next.map { $0.day == DayKey(now, calendar: context.calendar) } ?? false
        let canTake = next.map { isToday && MedPlan.state($0, doses: month.model.doses, now: now) == .due } ?? false
        WidgetCard(context: context, action: canTake ? WidgetQuickAction("Took it", symbolName: "checkmark") {
            if let next { MedLogging.mark(next, .taken, context: context) }
        } : nil) {
            if meds.isEmpty {
                WidgetUI.summary("Add your medications and get a reminder at each dose", theme: theme)
            } else if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.med.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    Text("\(isToday ? "" : "Tomorrow ")\(MedPlan.timeText(next.minutes, calendar: context.calendar))")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    todayDots(meds, now: now)
                }
            } else {
                WidgetUI.summary("All done for today ✅", theme: theme)
            }
        }
        .task {
            await settings.loadIfNeeded(); await month.loadIfNeeded()
            await MedReminderScheduler.sync(settings.model)
        }
    }

    private func todayDots(_ meds: [Med], now: Date) -> some View {
        let slots = MedPlan.slots(meds, on: DayKey(now, calendar: context.calendar), calendar: context.calendar)
        return HStack(spacing: 4) {
            ForEach(slots) { slot in
                let state = MedPlan.state(slot, doses: month.model.doses, now: now)
                Circle().fill(MedColors.color(state, theme: context.theme, accent: context.accent)).frame(width: 8, height: 8)
            }
        }
    }
}

enum MedColors {
    static func color(_ state: MedPlan.State, theme: WidgetTheme, accent: Color) -> Color {
        switch state {
        case .taken: return accent
        case .skipped: return theme.secondaryLabel
        case .missed: return theme.danger
        case .due: return theme.warning
        case .upcoming: return theme.tertiaryBackground
        }
    }
}

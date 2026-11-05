import SwiftUI
import FavWidgetsCore

/// Wake Up (Wes, 2026-11-05): real alarms that ring like the Clock app's,
/// even on silent, each with a station from Pandora, Spotify, Apple Music or
/// any music app. Stop opens the station; Snooze rings again in a few
/// minutes. Private to the person (generic share card).
public struct WakeUpWidget: FavWidget {
    public init() {}

    public static let widgetId = "wakeup"

    public let descriptor = FavWidgetDescriptor(
        id: WakeUpWidget.widgetId,
        title: "Wake Up",
        subtitle: "An alarm that opens your station",
        symbolName: "alarm.fill",
        accentHex: "#F08A24",
        category: .health,
        storage: .single,
        schemaVersion: AlarmClockSettings.schemaVersion,
        shareBlurb: "An alarm that wakes you up to your Pandora, Spotify or Apple Music station."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WakeUpCardView(context: context, settings: context.state(AlarmClockSettings.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(WakeUpFullView(context: context, settings: context.state(AlarmClockSettings.self)))
    }
}

/// Keeps the phone's alarms the same as the saved ones.
@MainActor
enum WakeUpSync {
    /// Switches off one-time alarms that already rang, then sets the phone's
    /// alarms. Returns an error to show, or nil.
    @discardableResult
    static func sync(_ settings: WidgetStateController<AlarmClockSettings>, context: WidgetContext) async -> String? {
        var model = settings.model
        if !AlarmClockPlan.expireRungOnce(&model, now: Date()).isEmpty {
            settings.update { $0 = model }
        }
        guard await context.host.alarmPermission() == .allowed else { return nil }
        do {
            try await context.host.syncAlarms(AlarmClockPlan.specs(settings.model))
            return nil
        } catch {
            return "Couldn't set your alarms on this iPhone: \(error.localizedDescription)"
        }
    }
}

struct WakeUpCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<AlarmClockSettings>

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: nil) {
            if let next = AlarmClockPlan.next(settings.model.alarms, after: Date(), calendar: context.calendar) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AlarmClockPlan.timeText(next.alarm.minutes, calendar: context.calendar))
                        .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
                    Text([AlarmClockPlan.ringsIn(next.at, from: Date()),
                          settings.model.station(id: next.alarm.stationId)?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
            } else {
                WidgetUI.summary(settings.model.alarms.isEmpty ? "Wake up to your Pandora or Spotify station"
                                                               : "No alarms on", theme: theme)
            }
        }
        .task {
            await settings.loadIfNeeded()
            await WakeUpSync.sync(settings, context: context)
        }
    }
}

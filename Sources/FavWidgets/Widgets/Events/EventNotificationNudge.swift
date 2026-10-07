import SwiftUI
import FavWidgetsCore

/// "Turn on notifications so you don't miss roll call" — on an event, when
/// this phone can't get its pushes. Asks right here if iPhone hasn't asked
/// yet; otherwise opens Settings (iPhone only asks once). Gone once they're
/// on; "Not now" hides it for this event on this phone.
struct EventNotificationNudge: View {
    let context: WidgetContext
    let event: EventSummary
    @State private var permission: WidgetNotificationPermission = .allowed
    @State private var dismissed = false
    @Environment(\.scenePhase) private var scenePhase

    private var dismissKey: String { "events.notificationNudge.dismissed.\(event.id)" }

    var body: some View {
        let theme = context.theme
        Group {
            if !dismissed, let nudge = EventCopy.notificationNudge(permission, eventName: event.name) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bell.badge.fill").font(.system(size: 20)).foregroundStyle(context.accent)
                        Text(nudge.message).font(.system(size: 14)).foregroundStyle(theme.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        Button { act() } label: {
                            Text(nudge.button).font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(context.accent)).foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Button("Not now") { dismiss() }
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(context.accent.opacity(0.12)))
            }
        }
        .task { await refresh() }
        // Back from Settings: re-check, and the card goes if they turned it on
        .onChange(of: scenePhase) { phase in if phase == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        dismissed = UserDefaults.standard.bool(forKey: dismissKey)
        permission = await context.host.notificationPermission()
    }

    private func act() {
        context.track("event_notification_nudge_tapped", ["state": permission.rawValue])
        if permission == .notDetermined {
            Task { @MainActor in
                _ = await context.host.requestNotificationPermission()
                permission = await context.host.notificationPermission()
            }
        } else {
            context.host.openNotificationSettings()
        }
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: dismissKey)
        withAnimation { dismissed = true }
        context.track("event_notification_nudge_dismissed")
    }
}

import SwiftUI
import FavWidgetsCore

/// Invite: a card + link for the group text, or a push to connections.
struct EventInviteSheet: View {
    let context: WidgetContext
    let event: EventSummary
    /// The event with its new "Invited" list
    var onInvited: (EventSummary) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [WidgetContact] = []
    @State private var picked: Set<String> = []
    @State private var sending = false

    var body: some View {
        let theme = context.theme
        let memberIds = Set(event.members.map(\.id))
        let invitedIds = Set(event.invitedPeople.map(\.id))
        WidgetSheet(title: "Invite to \(event.name)", theme: theme,
                    confirm: (label: sending ? "Sending…" : EventCopy.inviteButton(selected: picked.count), enabled: !picked.isEmpty && !sending, action: sendInvites),
                    cancelDisabled: sending) {
            List {
                Section {
                    EventInviteCard(event: event, accent: context.accent)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    Button { shareLink() } label: {
                        Label("Send the link to your group text", systemImage: "message.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                    }
                } footer: {
                    Text("Anyone with the link can join. They get the app, tap the link, and they're in (+1 FavCoin).")
                }
                Section("Or invite your connections") {
                    ForEach(contacts.filter { !memberIds.contains($0.id) }) { contact in
                        if invitedIds.contains(contact.id) {
                            HStack {
                                Text(contact.displayName).foregroundStyle(theme.label)
                                Spacer()
                                Text("Invited").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            }
                        } else {
                            Button { toggle(contact.id) } label: {
                                HStack {
                                    Text(contact.displayName).foregroundStyle(theme.label)
                                    Spacer()
                                    Image(systemName: picked.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(contact.id) ? context.accent : theme.secondaryLabel)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task { contacts = ((try? await context.host.fetchConnections()) ?? []).sorted { $0.displayName < $1.displayName } }
    }

    private func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        context.host.haptic(.selection)
    }

    /// One tappable bubble in Messages: the card image + the link.
    private func shareLink() {
        guard let url = event.inviteURL else { return }
        context.track("event_link_shared")
        context.host.share([.link(url, title: "\(event.emoji) Join \(event.name)", imageJPEG: EventInviteCard.jpeg(event: event, accent: context.accent))])
    }

    private func sendInvites() {
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let count = picked.count
                let updated = try await EventsClient(context: context).invite(event.id, userIds: Array(picked))
                context.host.haptic(.success)
                context.track("event_invited", ["count": "\(count)"])
                if let updated { onInvited(updated) }
                dismiss()
                context.host.presentAlert(WidgetAlert(title: "Invites sent",
                    message: "\(count) \(count == 1 ? "person was" : "people were") invited to \(event.name). They'll show as Invited until they join."))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send invites", message: "Check your connection and try again."))
            }
        }
    }
}

/// The invite card in the group text.
struct EventInviteCard: View {
    let event: EventSummary
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(event.emoji).font(.system(size: 64))
            Text(event.name).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Tap to join · photos only we can see").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            Text("FavCircles").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320, height: 240)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.24, blue: 0.5), accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    @MainActor
    static func jpeg(event: EventSummary, accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: EventInviteCard(event: event, accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}

import SwiftUI
import FavWidgetsCore

/// Who's in it. The coordinator removes people; everyone can connect with
/// the rest (which also fills their event Inner Circle list) or leave.
struct EventPeopleSection: View {
    let context: WidgetContext
    @ObservedObject var model: EventDetailModel
    let event: EventSummary
    let onGone: () -> Void
    @State private var connectedIds: Set<String> = []
    @State private var requested: Set<String> = []
    @State private var confirmEnd = false
    @State private var confirmLeave = false

    var body: some View {
        let theme = context.theme
        let myId = context.host.currentUserId
        let notConnected = EventCopy.notConnected(event, myId: myId, connectedIds: connectedIds).filter { !requested.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            if !notConnected.isEmpty {
                Button { connectAll(notConnected) } label: {
                    Label("Connect with everyone (\(notConnected.count))", systemImage: "person.3.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text("Connections land in your \(event.name) Inner Circle, so sharing with this crew later is one tap.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(event.members) { member in
                HStack(spacing: 12) {
                    EventAvatar(member: member, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.id == myId ? "\(member.name) (you)" : member.name)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        if member.isHost { Text("Coordinator").font(.system(size: 12)).foregroundStyle(context.accent) }
                        else if requested.contains(member.id) { Text("Request sent").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel) }
                    }
                    Spacer()
                    if event.isHost && member.id != myId {
                        Menu {
                            Button(role: .destructive) { remove(member) } label: { Label("Remove from \(event.name)", systemImage: "person.fill.xmark") }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(theme.secondaryLabel).frame(width: 32, height: 32) }
                    }
                }
                .padding(.vertical, 4)
            }
            if !event.invitedPeople.isEmpty {
                Text("Invited").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel).padding(.top, 6)
                ForEach(event.invitedPeople) { person in
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.badge").font(.system(size: 18)).foregroundStyle(context.accent).frame(width: 40)
                        Text(person.name).font(.system(size: 15)).foregroundStyle(theme.label)
                        Spacer()
                        Text("Hasn't joined yet").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
            Divider().overlay(theme.separator)
            if event.isHost {
                Button(role: .destructive) { confirmEnd = true } label: { Text("End event").font(.system(size: 15, weight: .semibold)) }
                Text("Ending it removes the album and places for everyone. Circles people saved stay theirs.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            } else {
                Button(role: .destructive) { confirmLeave = true } label: { Text("Leave \(event.name)").font(.system(size: 15, weight: .semibold)) }
            }
        }
        .task {
            if let contacts = try? await context.host.fetchConnections() { connectedIds = Set(contacts.map(\.id)) }
        }
        .confirmationDialog("End \(event.name)?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End event", role: .destructive) { end() }
        }
        .confirmationDialog("Leave \(event.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leave() }
        }
    }

    private func connectAll(_ members: [EventSummary.Member]) {
        Task { @MainActor in
            let client = EventsClient(context: context)
            for member in members {
                if (try? await client.connect(userId: member.id)) != nil { requested.insert(member.id) }
            }
            context.host.haptic(.success)
            context.track("event_connect_all", ["count": "\(members.count)"])
        }
    }

    private func remove(_ member: EventSummary.Member) {
        Task { @MainActor in
            if (try? await EventsClient(context: context).remove(model.eventId, member: member.id)) != nil { await model.load() }
        }
    }

    private func end() {
        Task { @MainActor in
            if (try? await EventsClient(context: context).end(model.eventId)) != nil { onGone() }
        }
    }

    private func leave() {
        Task { @MainActor in
            if (try? await EventsClient(context: context).leave(model.eventId)) != nil { onGone() }
        }
    }
}

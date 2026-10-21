import SwiftUI
import FavWidgetsCore

/// The next meetup or event: when, where, who's going, and my answer.
struct ClubNextUpSection: View {
    let context: WidgetContext
    let club: Club
    let onRSVP: (ClubOccurrence, ClubRSVP?) -> Void
    let onOpenSpot: (ClubSpot) -> Void

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Next up", theme: theme)
            if let next = club.upcoming.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.title.isEmpty ? club.name : next.title)
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(theme.label)
                        if next.isEvent {
                            Text("EVENT").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(context.accent))
                        }
                    }
                    Label(ClubCopy.relative(next.startsAt, timeZone: club.timeZone), systemImage: "clock")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                    if let spot = next.spot {
                        Button { onOpenSpot(spot) } label: {
                            Label(spot.name, systemImage: "mappin.and.ellipse").font(.system(size: 14)).foregroundStyle(theme.label)
                        }
                        .buttonStyle(.plain)
                    }
                    if let notes = next.notes, !notes.isEmpty {
                        Text(notes).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ClubGoingRow(context: context, occurrence: next)
                    HStack(spacing: 10) {
                        rsvpButton("Going", symbol: "checkmark", selected: next.myRsvp == .going) {
                            onRSVP(next, next.myRsvp == .going ? nil : .going)
                        }
                        rsvpButton("Can't make it", symbol: "xmark", selected: next.myRsvp == .not) {
                            onRSVP(next, next.myRsvp == .not ? nil : .not)
                        }
                    }
                    if next.myRsvp == .going {
                        Text("We'll remind you an hour before.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
            } else {
                Text(club.canOrganize
                     ? "Nothing scheduled. Add the days and times you meet below, or a one-off event."
                     : "Nothing scheduled yet. The organizers will add meetups here.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rsvpButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? context.accent : context.theme.tertiaryBackground))
                .foregroundStyle(selected ? .white : context.theme.label)
        }
        .buttonStyle(.plain)
    }
}

/// Faces and "Ana, Joe and 4 others going".
struct ClubGoingRow: View {
    let context: WidgetContext
    let occurrence: ClubOccurrence

    var body: some View {
        let theme = context.theme
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(occurrence.going.prefix(5)) { person in
                    ClubAvatar(name: person.name, url: person.avatarUrl, size: 26, theme: theme)
                        .overlay(Circle().stroke(theme.secondaryBackground, lineWidth: 2))
                }
            }
            Text(ClubCopy.goingLine(occurrence.going, meId: context.host.currentUserId)
                 + (occurrence.notGoingCount > 0 ? " · \(occurrence.notGoingCount) can't" : ""))
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
        }
    }
}

/// Weekly meetups, one-off events, and the dates coming up.
struct ClubScheduleSection: View {
    let context: WidgetContext
    let club: Club
    let onAddMeetup: () -> Void
    let onEditMeetup: (ClubMeetup) -> Void
    let onAddEvent: () -> Void
    let onDeleteEvent: (ClubEvent) -> Void
    let onRSVP: (ClubOccurrence, ClubRSVP?) -> Void

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Schedule", theme: theme)
            ForEach(club.schedule.sorted { ($0.weekday, $0.time) < ($1.weekday, $1.time) }) { meetup in
                Button { if club.canOrganize { onEditMeetup(meetup) } } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "repeat").foregroundStyle(context.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ClubCopy.meetupLine(meetup)) · \(meetup.title)")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            if let spot = meetup.spot ?? club.homeSpot {
                                Text(spot.name).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                            }
                            if let notes = meetup.notes, !notes.isEmpty {
                                Text(notes).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                        Spacer()
                        if club.canOrganize { Image(systemName: "pencil").foregroundStyle(theme.secondaryLabel) }
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(club.events) { event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "star.circle.fill").foregroundStyle(context.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text([ClubCopy.occurrenceLine(event.startsAt, timeZone: club.timeZone), ClubCopy.spotLine(event.spot ?? club.homeSpot)]
                             .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                }
                .contextMenu {
                    if club.canOrganize { Button("Delete event", role: .destructive) { onDeleteEvent(event) } }
                }
            }
            if club.schedule.isEmpty && club.events.isEmpty && !club.canOrganize {
                Text("No regular meetups yet.").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            if club.canOrganize {
                HStack(spacing: 16) {
                    Button(action: onAddMeetup) {
                        Label("Weekly meetup", systemImage: "plus.circle").font(.system(size: 14, weight: .semibold))
                    }
                    Button(action: onAddEvent) {
                        Label("One-off event", systemImage: "plus.circle").font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(context.accent)
                .buttonStyle(.plain)
            }
            let later = Array(club.upcoming.dropFirst())
            if !later.isEmpty {
                Text("Coming up").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel).padding(.top, 6)
                ForEach(later) { occ in upcomingRow(occ, theme: theme) }
            }
        }
    }

    private func upcomingRow(_ occ: ClubOccurrence, theme: WidgetTheme) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ClubCopy.occurrenceLine(occ.startsAt, timeZone: club.timeZone))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                Text([occ.title, occ.going.isEmpty ? nil : ClubCopy.goingCount(occ.going.count)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
            }
            Spacer()
            Menu {
                Button { onRSVP(occ, .going) } label: { Label("Going", systemImage: "checkmark") }
                Button { onRSVP(occ, .not) } label: { Label("Can't make it", systemImage: "xmark") }
                if occ.myRsvp != nil { Button("Clear my answer") { onRSVP(occ, nil) } }
            } label: {
                Text(occ.myRsvp == .going ? "Going" : occ.myRsvp == .not ? "Can't" : "Going?")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(occ.myRsvp == .going ? context.accent : theme.tertiaryBackground))
                    .foregroundStyle(occ.myRsvp == .going ? .white : theme.label)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Organizers first, then everyone by name.
struct ClubPeopleSection: View {
    let context: WidgetContext
    let club: Club
    let onInvite: () -> Void
    let onTap: (ClubMember) -> Void

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header("People · \(club.memberCount)", theme: theme)
                Spacer()
                Button(action: onInvite) {
                    Label("Invite", systemImage: "person.badge.plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
            }
            ForEach(club.members) { member in
                Button { onTap(member) } label: {
                    HStack(spacing: 10) {
                        ClubAvatar(name: member.name, url: member.avatarUrl, size: 34, theme: theme)
                        Text(member.userId == context.host.currentUserId ? "\(member.name) (you)" : member.name)
                            .font(.system(size: 15)).foregroundStyle(theme.label)
                        Spacer()
                        if member.role != .member {
                            Text(member.role.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(context.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Invite: the club card + link for a group text, or a push to connections.
struct ClubInviteSheet: View {
    let context: WidgetContext
    let club: Club
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [WidgetContact] = []
    @State private var picked: Set<String> = []
    @State private var sending = false

    var body: some View {
        let theme = context.theme
        let memberIds = Set(club.members.map(\.userId))
        WidgetSheet(title: "Invite to \(club.name)", theme: theme,
                    confirm: (label: sending ? "Sending…" : (picked.isEmpty ? "Invite" : "Invite \(picked.count)"),
                              enabled: !picked.isEmpty && !sending, action: sendInvites),
                    cancelDisabled: sending) {
            List {
                Section {
                    ClubInviteCard(club: club, accent: context.accent)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    Button { shareLink() } label: {
                        Label("Send the link to your group", systemImage: "message.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    .disabled(club.inviteURL == nil)
                } footer: {
                    Text(club.joinOpen
                         ? "Anyone with the link can join. They get the app, tap the link, and they're in."
                         : "New members can't join right now. Turn joining back on in the club's settings.")
                }
                Section("Or invite your connections") {
                    ForEach(contacts.filter { !memberIds.contains($0.id) }) { contact in
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
        .task { contacts = ((try? await context.host.fetchConnections()) ?? []).sorted { $0.displayName < $1.displayName } }
    }

    private func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        context.host.haptic(.selection)
    }

    /// One tappable bubble in Messages: the card image + the link.
    private func shareLink() {
        guard let url = club.inviteURL else { return }
        context.track("club_link_shared")
        context.host.share([.link(url, title: "\(club.emoji) Join \(club.name)", imageJPEG: ClubInviteCard.jpeg(club: club, accent: context.accent))])
    }

    private func sendInvites() {
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let count = try await ClubsClient(context: context).invite(club.id, userIds: Array(picked))
                context.host.haptic(.success)
                context.track("club_invited", ["count": "\(count)"])
                dismiss()
                context.host.presentAlert(WidgetAlert(title: "Invites sent",
                    message: "\(count) \(count == 1 ? "person was" : "people were") invited to \(club.name)."))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send invites", message: (error as NSError).localizedDescription))
            }
        }
    }
}

/// The club card in a group text.
struct ClubInviteCard: View {
    let club: Club
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(club.emoji).font(.system(size: 60))
            Text(club.name).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(2)
            if let line = ClubCopy.scheduleLine(club.schedule, server: club.scheduleLine) {
                Text(line).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            Text("Tap to join · \(ClubCopy.memberCount(club.memberCount))").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            Text("FavCircles").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7)).padding(.top, 2)
        }
        .padding(22)
        .frame(width: 320, height: 240)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.2), accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    @MainActor
    static func jpeg(club: Club, accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: ClubInviteCard(club: club, accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}

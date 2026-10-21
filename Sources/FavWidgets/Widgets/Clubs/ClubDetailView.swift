import SwiftUI
import FavWidgetsCore

/// One club: what's next and who's going, the weekly schedule and events,
/// the bulletin, the board, the people, and (for organizers) running it.
struct ClubDetailView: View {
    let context: WidgetContext
    let clubId: String
    /// A push asked for this post: open its thread once the club loads
    var openPostId: String?
    let onGone: () -> Void
    let onChange: (Club) -> Void

    @StateObject private var model: ClubDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: Sheet?
    @State private var thread: ClubPost?
    @State private var memberActions: ClubMember?
    @State private var confirmEnd = false
    @State private var confirmLeave = false
    @State private var busy = false
    @State private var openedPost = false

    enum Sheet: Identifiable {
        case edit, addMeetup, editMeetup(ClubMeetup), addEvent, compose(String), list(String), invite
        var id: String {
            switch self {
            case .edit: return "edit"
            case .addMeetup: return "addMeetup"
            case .editMeetup(let m): return "meetup-\(m.id)"
            case .addEvent: return "addEvent"
            case .compose(let kind): return "compose-\(kind)"
            case .list(let kind): return "list-\(kind)"
            case .invite: return "invite"
            }
        }
    }

    init(context: WidgetContext, clubId: String, openPostId: String? = nil, onGone: @escaping () -> Void, onChange: @escaping (Club) -> Void) {
        self.context = context
        self.clubId = clubId
        self.openPostId = openPostId
        self.onGone = onGone
        self.onChange = onChange
        _model = StateObject(wrappedValue: ClubDetailModel(clubId: clubId, context: context))
    }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            Group {
                if let club = model.club {
                    content(club, theme: theme)
                } else if let error = model.error {
                    VStack(spacing: 12) {
                        Text(error).font(.system(size: 15)).foregroundStyle(theme.label).multilineTextAlignment(.center)
                        Button("Try again") { Task { await model.load() } }
                    }
                    .padding(24)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(model.club?.name ?? "Club")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let club = model.club {
                    ToolbarItem(placement: .primaryAction) {
                        Button { sheet = .invite } label: { Image(systemName: "person.badge.plus") }
                            .accessibilityLabel("Invite to \(club.name)")
                    }
                }
            }
        }
        .task {
            await model.load()
            if let club = model.club { onChange(club) }
            await openRequestedPost()
        }
        .sheet(item: $sheet) { sheet in sheetView(sheet) }
        .sheet(item: $thread) { post in
            if let club = model.club {
                ClubThreadView(context: context, club: club, post: post) { _ in Task { await reload() } }
            }
        }
        .confirmationDialog(memberActions?.name ?? "", isPresented: Binding(get: { memberActions != nil }, set: { if !$0 { memberActions = nil } }),
                            titleVisibility: .visible, presenting: memberActions) { member in
            memberButtons(member)
        }
        .alert("End this club?", isPresented: $confirmEnd) {
            Button("End club", role: .destructive) { endClub() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The club, its schedule, bulletin and board are removed for everyone. This can't be undone.")
        }
        .alert("Leave this club?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive) { leave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can rejoin later with the club's link.")
        }
    }

    // MARK: - Page

    private func content(_ club: Club, theme: WidgetTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(club, theme: theme)
                ClubNextUpSection(context: context, club: club, onRSVP: { rsvp($0, $1) }, onOpenSpot: openSpot)
                ClubScheduleSection(context: context, club: club,
                                    onAddMeetup: { sheet = .addMeetup }, onEditMeetup: { sheet = .editMeetup($0) },
                                    onAddEvent: { sheet = .addEvent }, onDeleteEvent: deleteEvent,
                                    onRSVP: { rsvp($0, $1) })
                postsSection(club, kind: "bulletin", theme: theme)
                postsSection(club, kind: "board", theme: theme)
                ClubPeopleSection(context: context, club: club, onInvite: { sheet = .invite }) { member in
                    if canAct(on: member, in: club) { memberActions = member }
                }
                settings(club, theme: theme)
            }
            .padding(16)
        }
        .refreshable { await reload() }
    }

    private func header(_ club: Club, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(club.emoji).font(.system(size: 44))
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(context.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(club.name).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
                    Text("\(club.kind.label) · \(ClubCopy.memberCount(club.memberCount))")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    if let line = ClubCopy.scheduleLine(club.schedule, server: club.scheduleLine) {
                        Label(line, systemImage: "calendar").font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                    }
                }
            }
            if !club.description.isEmpty {
                Text(club.description).font(.system(size: 15)).foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let spot = club.homeSpot {
                Button { openSpot(spot) } label: {
                    Label(spot.address.map { "\(spot.name) · \($0)" } ?? spot.name, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                }
                .buttonStyle(.plain)
            }
            if club.muted {
                Label("You muted this club: no notifications from it", systemImage: "bell.slash")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    private func postsSection(_ club: Club, kind: String, theme: WidgetTheme) -> some View {
        let isBulletin = kind == "bulletin"
        let posts = isBulletin ? club.bulletin : club.boardPreview
        let canPost = !isBulletin || club.canOrganize
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header(isBulletin ? "Bulletin" : "Board", theme: theme)
                Spacer()
                if canPost {
                    Button { sheet = .compose(kind) } label: {
                        Label(isBulletin ? "Announce" : "Post", systemImage: isBulletin ? "megaphone" : "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if posts.isEmpty {
                Text(isBulletin
                     ? (club.canOrganize ? "Announcements go here, and everyone gets a notification." : "No announcements yet.")
                     : "Talk with the club: plans, photos, questions.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(posts) { post in
                ClubPostRow(context: context, post: post, onOpen: { thread = post }) { react(post, $0) }
            }
            if !posts.isEmpty {
                Button { sheet = .list(kind) } label: {
                    Text(isBulletin ? "All announcements" : "The whole board")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func settings(_ club: Club, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Club", theme: theme)
            Toggle(isOn: Binding(get: { !club.muted }, set: { setMuted(!$0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications").font(.system(size: 15)).foregroundStyle(theme.label)
                    Text("Announcements, new events and replies to your posts").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .tint(context.accent)
            if club.canOrganize {
                Button("Edit club details") { sheet = .edit }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                Toggle(isOn: Binding(get: { club.joinOpen }, set: { setJoinOpen($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New members can join").font(.system(size: 15)).foregroundStyle(theme.label)
                        Text("Off: the link stops letting people in").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
                Button("Reset the invite link") { resetLink() }
                    .font(.system(size: 15)).foregroundStyle(context.accent)
            }
            if club.isOwner {
                Button("End club", role: .destructive) { confirmEnd = true }.font(.system(size: 15))
            } else {
                Button("Leave club", role: .destructive) { confirmLeave = true }.font(.system(size: 15))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
        .disabled(busy)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(_ sheet: Sheet) -> some View {
        if let club = model.club {
            switch sheet {
            case .edit:
                ClubEditSheet(context: context, club: club) { apply($0) }
            case .addMeetup:
                ClubMeetupEditor(context: context, club: club, meetup: nil) { apply($0) }
            case .editMeetup(let meetup):
                ClubMeetupEditor(context: context, club: club, meetup: meetup) { apply($0) }
            case .addEvent:
                ClubEventEditor(context: context, club: club) { apply($0) }
            case .compose(let kind):
                ClubPostComposer(context: context, club: club, kind: kind) { _ in Task { await reload() } }
            case .list(let kind):
                ClubPostListView(context: context, club: club, kind: kind)
                    .onDisappear { Task { await reload() } }
            case .invite:
                ClubInviteSheet(context: context, club: club)
            }
        }
    }

    // MARK: - People

    private func canAct(on member: ClubMember, in club: Club) -> Bool {
        guard member.userId != context.host.currentUserId, member.role != .owner else { return false }
        return club.canOrganize
    }

    @ViewBuilder
    private func memberButtons(_ member: ClubMember) -> some View {
        if let club = model.club {
            if club.isOwner {
                if member.role == .organizer {
                    Button("Make a member (not an organizer)") { setRole(member, .member) }
                } else {
                    Button("Make an organizer") { setRole(member, .organizer) }
                }
            }
            Button("Remove from \(club.name)", role: .destructive) { remove(member) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Actions

    private var client: ClubsClient { model.client }

    private func reload() async {
        await model.load()
        if let club = model.club { onChange(club) }
    }

    private func apply(_ club: Club) {
        model.club = club
        onChange(club)
    }

    private func perform(_ title: String, _ op: @escaping () async throws -> Club?) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                if let club = try await op() { apply(club) }
            } catch {
                context.host.presentAlert(WidgetAlert(title: title, message: (error as NSError).localizedDescription))
            }
        }
    }

    private func rsvp(_ occurrence: ClubOccurrence, _ status: ClubRSVP?) {
        guard let club = model.club else { return }
        let me = context.host.currentUserId.map { id in
            ClubPerson(userId: id, name: club.members.first { $0.userId == id }?.name ?? "You",
                       avatarUrl: club.members.first { $0.userId == id }?.avatarUrl)
        }
        let previous = occurrence
        model.club = club.replacing(occurrence.with(myRsvp: status, me: me))
        context.host.haptic(.selection)
        Task { @MainActor in
            do {
                let saved = try await client.rsvp(club.id, key: occurrence.key, status: status)
                if let current = model.club { apply(current.replacing(saved)) }
                context.track("club_rsvp", ["status": status?.rawValue ?? "cleared"])
                await ClubReminders.sync(saved, clubName: club.name, emoji: club.emoji, quietHours: context.host.quietHours)
            } catch {
                if let current = model.club { model.club = current.replacing(previous) }
                context.host.presentAlert(WidgetAlert(title: "Couldn't save that", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func react(_ post: ClubPost, _ emoji: String?) {
        guard let club = model.club else { return }
        Task { @MainActor in
            if (try? await client.react(club.id, post: post.id, emoji: emoji)) != nil { await reload() }
        }
    }

    private func deleteEvent(_ event: ClubEvent) {
        guard let club = model.club else { return }
        perform("Couldn't delete the event") { try await client.deleteEvent(club.id, event: event.id) }
    }

    private func setMuted(_ muted: Bool) {
        guard let club = model.club else { return }
        perform("Couldn't change notifications") { try await client.mute(club.id, muted) }
    }

    private func setJoinOpen(_ open: Bool) {
        guard let club = model.club else { return }
        perform("Couldn't change that") { try await client.update(club.id, ["joinOpen": open]) }
    }

    private func resetLink() {
        guard let club = model.club else { return }
        perform("Couldn't reset the link") {
            let updated = try await client.resetLink(club.id)
            context.host.presentAlert(WidgetAlert(title: "New link ready", message: "The old link no longer works. Share the new one from Invite."))
            return updated
        }
    }

    private func setRole(_ member: ClubMember, _ role: ClubRole) {
        guard let club = model.club else { return }
        perform("Couldn't change that") { try await client.setRole(club.id, member: member.userId, role: role) }
    }

    private func remove(_ member: ClubMember) {
        guard let club = model.club else { return }
        perform("Couldn't remove \(ClubCopy.firstName(member.name))") { try await client.remove(club.id, member: member.userId) }
    }

    private func leave() {
        guard let club = model.club else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await client.leave(club.id)
                ClubReminders.cancel(club.upcoming)
                context.track("club_left")
                onGone()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't leave", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func endClub() {
        guard let club = model.club else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await client.end(club.id)
                ClubReminders.cancel(club.upcoming)
                context.track("club_ended")
                onGone()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't end the club", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func openSpot(_ spot: ClubSpot) {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        if let lat = spot.lat, let lng = spot.lng {
            parts.queryItems = [URLQueryItem(name: "ll", value: "\(lat),\(lng)"), URLQueryItem(name: "q", value: spot.name)]
        } else {
            parts.queryItems = [URLQueryItem(name: "q", value: [spot.name, spot.address].compactMap { $0 }.joined(separator: ", "))]
        }
        if let url = parts.url { context.host.openURL(url) }
    }

    /// A bulletin or reply push named a post: open its thread on top.
    private func openRequestedPost() async {
        guard !openedPost, let postId = openPostId, let club = model.club else { return }
        openedPost = true
        if let post = (club.bulletin + club.boardPreview).first(where: { $0.id == postId }) {
            await context.waitForPageToSettle()
            thread = post
            return
        }
        // Older than the previews: look on the bulletin, then the board
        for kind in ["bulletin", "board"] {
            if let page = try? await client.posts(club.id, kind: kind), let post = page.posts.first(where: { $0.id == postId }) {
                await context.waitForPageToSettle()
                thread = post
                return
            }
        }
    }
}

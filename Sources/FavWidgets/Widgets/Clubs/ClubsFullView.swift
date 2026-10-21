import SwiftUI
import FavWidgetsCore

/// Your clubs, "Start a club", joining from a pasted link, and where links
/// and pushes land (join screen, a club, a post on a club).
struct ClubsFullView: View {
    let context: WidgetContext
    @ObservedObject var store: ClubsStore

    @State private var creating = false
    @State private var openClub: ClubRef?
    @State private var joinToken: TokenRef?
    @State private var pasting = false
    @State private var pasted = ""

    struct ClubRef: Identifiable { let id: String; var postId: String? = nil }
    struct TokenRef: Identifiable { let id: String }

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(theme)
                if store.clubs.isEmpty && store.hasLoaded {
                    Text("No clubs yet. Start one, set the days and times you meet, and send the link to your group. Got a link from someone? Tap it, or paste it below.")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(store.clubs) { club in
                    Button { openClub = ClubRef(id: club.id) } label: { row(club, theme: theme) }
                        .buttonStyle(.plain)
                }
                Button { pasting = true } label: {
                    Label("Join with a link", systemImage: "link")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                if let error = store.loadError, store.clubs.isEmpty {
                    Text(error).font(.system(size: 13)).foregroundStyle(theme.warning)
                }
            }
            .padding(16)
        }
        .refreshable { await store.refresh(context, force: true) }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await store.refresh(context) }
        .task { await openLaunched() }
        .sheet(isPresented: $creating) {
            ClubEditSheet(context: context, club: nil) { club in
                store.upsert(club.summary)
                openAfterSheetCloses(club.id)
            }
        }
        .sheet(item: $joinToken) { token in
            ClubJoinSheet(context: context, token: token.id) { club in
                store.upsert(club.summary)
                openAfterSheetCloses(club.id)
            }
        }
        .alert("Join with a link", isPresented: $pasting) {
            TextField("Paste the club link", text: $pasted)
            Button("Cancel", role: .cancel) { pasted = "" }
            Button("Continue") { usePasted() }
        } message: {
            Text("Paste the link someone sent you.")
        }
        .fullScreenCoverOrSheet(item: $openClub) { ref in
            ClubDetailView(context: context, clubId: ref.id, openPostId: ref.postId, onGone: {
                store.remove(ref.id)
                openClub = nil
            }, onChange: { store.upsert($0.summary) })
        }
    }

    private func hero(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🏃📚🚴").font(.system(size: 34))
            Text("Your club, all in one place")
                .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Who's in, when and where you meet, who's going this week, and a board to talk on. Start one and send the link to your group.")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Button { creating = true } label: {
                Label("Start a club", systemImage: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                    .foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.2), context.accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func row(_ club: ClubSummary, theme: WidgetTheme) -> some View {
        HStack(spacing: 12) {
            Text(club.emoji).font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Circle().fill(context.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(club.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                if let next = club.next {
                    Text("Next: \(ClubCopy.relative(next.startsAt))\(next.going.isEmpty ? "" : " · \(ClubCopy.goingCount(next.going.count))")")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                } else {
                    Text("\(ClubCopy.memberCount(club.memberCount)) · nothing scheduled")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                if club.myRole.canOrganize {
                    Text(club.myRole == .owner ? "You run this club" : "You're an organizer")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(context.accent)
                }
            }
            Spacer()
            if club.muted { Image(systemName: "bell.slash").foregroundStyle(theme.secondaryLabel) }
            Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
    }

    private func usePasted() {
        let text = pasted
        pasted = ""
        guard let token = ClubCopy.token(fromPasted: text) else {
            context.host.presentAlert(WidgetAlert(title: "That isn't a club link", message: "Ask for the club's link and paste the whole thing."))
            return
        }
        joinToken = TokenRef(id: token)
    }

    /// Opening a page while a sheet is still animating away flashed and
    /// closed it (the 0.23.3 bug class), so wait for the page to settle.
    private func openAfterSheetCloses(_ id: String) {
        Task { @MainActor in
            await context.waitForPageToSettle()
            openClub = ClubRef(id: id)
        }
    }

    /// A link or invite (join screen), or a push (a club, maybe a post on it).
    private func openLaunched() async {
        if let token = context.launchClubToken {
            context.launchClubToken = nil
            await context.waitForPageToSettle()
            joinToken = TokenRef(id: token)
        } else if let id = context.launchClubId {
            let postId = context.launchClubPostId
            context.launchClubId = nil
            context.launchClubPostId = nil
            await context.waitForPageToSettle()
            openClub = ClubRef(id: id, postId: postId)
        }
    }
}

/// Where a link or invite lands: what the club is, and one big Join.
struct ClubJoinSheet: View {
    let context: WidgetContext
    let token: String
    let onJoined: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ClubInvitePreview?
    @State private var failed: String?
    @State private var busy = false
    @State private var celebrate = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let preview {
                        Text(preview.emoji).font(.system(size: 92))
                            .scaleEffect(celebrate ? 1.25 : 1).rotationEffect(.degrees(celebrate ? 8 : 0))
                            .animation(.spring(response: 0.35, dampingFraction: 0.45), value: celebrate)
                        Text(preview.name).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
                            .multilineTextAlignment(.center)
                        Text("\(preview.kind.label) · \(ClubCopy.memberCount(preview.memberCount)) · run by \(preview.ownerName)")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
                        if let line = preview.scheduleLine, !line.isEmpty {
                            Label(line, systemImage: "calendar").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        }
                        if !preview.description.isEmpty {
                            Text(preview.description).font(.system(size: 15)).foregroundStyle(theme.label)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        Group {
                            if preview.alreadyMember {
                                WidgetUI.primaryButton("You're in, open it", color: context.accent) { openExisting(preview) }
                            } else if !preview.joinOpen {
                                Text("This club isn't taking new members right now.").font(.system(size: 15)).foregroundStyle(theme.warning)
                            } else {
                                WidgetUI.primaryButton(busy ? "Joining…" : ClubCopy.joinButton(preview), color: context.accent) { join() }
                                    .disabled(busy)
                                Text("See when and where the club meets, say you're going, and talk with everyone on the board.")
                                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 8)
                    } else if let failed {
                        Text(failed).font(.system(size: 16)).foregroundStyle(theme.label).multilineTextAlignment(.center)
                            .padding(.top, 60)
                    } else {
                        ProgressView().padding(.top, 60)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            do { preview = try await ClubsClient(context: context).preview(token: token) }
            catch { failed = "That club link isn't valid anymore. Ask for a fresh one." }
        }
    }

    private func join() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await ClubsClient(context: context).join(token: token)
                celebrate = true
                context.host.haptic(.success)
                context.track("club_joined")
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
                onJoined(result.club)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't join", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func openExisting(_ preview: ClubInvitePreview) {
        Task { @MainActor in
            if let club = try? await ClubsClient(context: context).detail(preview.id) {
                dismiss()
                onJoined(club)
            }
        }
    }
}

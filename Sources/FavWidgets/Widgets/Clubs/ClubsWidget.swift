import SwiftUI
import FavWidgetsCore

/// Clubs (Wes, 2026-10-21: "Think a run club. People, event, days times,
/// bulletin board or message board. Maybe both."). A club has members who
/// join by link, weekly meetups and one-off events with Going / Can't make
/// it, a bulletin organizers post to (it notifies everyone) and a board
/// anyone can post on. Server-backed (`/api/widgets/clubs`).
public struct ClubsWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "clubs",
        title: "Clubs",
        subtitle: "Your run club, book club or any club: who, when, where",
        symbolName: "figure.run.circle.fill",
        accentHex: "#FF6B2C",
        category: .social,
        storage: .none,
        shareBlurb: "Start a club (a run club, a book club, anything): members join with one link, see the weekly meetups and events, say they're going, and talk on the club's board."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(ClubsCardView(context: context, store: ClubsStore.shared(in: context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(ClubsFullView(context: context, store: ClubsStore.shared(in: context)))
    }

    public func refresh(context: WidgetContext) async {
        await ClubsStore.shared(in: context).refresh(context, force: true)
    }

    /// The club with the soonest meetup (or the first one): its name,
    /// schedule and size, linking to its join page. No club → generic.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let store = ClubsStore.shared(in: context)
        await store.refresh(context)
        guard let pick = ClubCopy.soonest(store.clubs)?.club ?? store.clubs.first,
              let club = try? await ClubsClient(context: context).detail(pick.id) else { return nil }
        return ClubsWidget.shareCardContent(club)
    }

    static func shareCardContent(_ club: Club) -> WidgetShareCardContent {
        var stats = [WidgetShareCardContent.Stat("\(club.memberCount)", club.memberCount == 1 ? "member" : "members")]
        if let next = club.upcoming.first {
            stats.append(.init(ClubCopy.relative(next.startsAt, timeZone: club.timeZone), "next meetup"))
        }
        return WidgetShareCardContent(
            headline: "\(club.emoji) \(club.name)",
            detail: ClubCopy.scheduleLine(club.schedule, server: club.scheduleLine) ?? club.kind.label,
            stats: stats,
            linkTitle: "\(club.emoji) Join \(club.name)",
            url: club.inviteURL
        )
    }
}

/// Card: the soonest meetup across your clubs, or the pitch.
struct ClubsCardView: View {
    let context: WidgetContext
    @ObservedObject var store: ClubsStore

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction("New", symbolName: "plus") { context.openFullView() }) {
            if let (club, next) = ClubCopy.soonest(store.clubs) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(club.emoji) \(next.title.isEmpty ? club.name : next.title)")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.label).lineLimit(1)
                    Text(ClubCopy.cardLine(club: club.name, next: next))
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
            } else if let club = store.clubs.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(club.emoji) \(club.name)")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.label).lineLimit(1)
                    Text("\(ClubCopy.memberCount(club.memberCount)) · nothing scheduled")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            } else {
                WidgetUI.summary("Start or join a club 🏃 runs, rides, books, anything", theme: theme)
            }
        }
        .task { await store.refresh(context) }
    }
}

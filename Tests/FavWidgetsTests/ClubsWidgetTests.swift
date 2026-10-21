import Foundation
import Testing
import FavWidgetsCore
@testable import FavWidgets

/// Clubs (2026-10-21): the share card says which club and links to joining it.
@MainActor
struct ClubsWidgetTests {
    @Test func shareCardNamesTheClubAndLinksToJoin() {
        let club = Club(id: "c1", name: "Charlotte Run Club", emoji: "🏃", kind: .run, memberCount: 12, myRole: .owner,
                        inviteLink: "https://api.favcircles.com/app/club/abcdefghijklmnop",
                        schedule: [ClubMeetup(id: "m", weekday: 6, time: "07:00", title: "Long run")],
                        upcoming: [ClubOccurrence(key: "k", kind: "meetup", title: "Long run", startsAt: Date().addingTimeInterval(86400))])
        let card = ClubsWidget.shareCardContent(club)
        #expect(card.headline == "🏃 Charlotte Run Club")
        #expect(card.detail == "Saturdays 7 AM")
        #expect(card.stats.first?.value == "12" && card.stats.count == 2)
        #expect(card.url?.absoluteString == "https://api.favcircles.com/app/club/abcdefghijklmnop")
        #expect(card.linkTitle == "🏃 Join Charlotte Run Club")
    }

    @Test func noClubsMeansTheGenericCard() async {
        let widget = FavWidgetRegistry.widget(id: "clubs")!
        let model = WidgetsTabModel(host: MockWidgetHost(), theme: .default)
        #expect(await widget.shareCard(context: model.context(for: widget.descriptor)) == nil)
    }
}

import Testing
import Foundation
@testable import FavWidgetsCore

/// Share on a finished workout sends one bubble: the card, as a link.
struct WorkoutShareLinkTests {

    private let summary = WorkoutShareSummary(
        name: "Chest and Back", startedAt: Date(), durationSeconds: 78 * 60, completedSets: 18,
        exercises: [.init(name: "Bench Press", sets: 4, bestSet: "185 lb × 4", isPR: false)],
        cardio: [], prCount: 0, unit: "lb", routine: nil)
    private let url = URL(string: "https://api.favcircles.com/app/workout/abcdefghijklmnopqrstuv")!
    private let card = Data([0xFF, 0xD8])

    @Test func withALinkItIsOneTappableCardAndNoText() {
        let items = WorkoutShareLink.items(url: url, summary: summary, cardJPEG: card)
        #expect(items.count == 1)
        guard case .link(let link, let title, let image) = items.first else { Issue.record("expected a link"); return }
        #expect(link == url)
        #expect(title == "Chest and Back · 78 min")
        #expect(image == card)
    }

    @Test func offlineTheCardAloneThenTextAsALastResort() {
        let offline = WorkoutShareLink.items(url: nil, summary: summary, cardJPEG: card)
        guard case .imageJPEG = offline.first, offline.count == 1 else { Issue.record("expected the card alone"); return }
        let bare = WorkoutShareLink.items(url: nil, summary: summary, cardJPEG: nil)
        guard case .text(let text) = bare.first else { Issue.record("expected text"); return }
        #expect(text.contains("Chest and Back"))
    }
}

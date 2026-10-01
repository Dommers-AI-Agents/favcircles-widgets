import Testing
import Foundation
@testable import FavWidgetsCore

/// "Show older answers" on a check-in.
struct CareHistoryPagingTests {

    private func ask(_ id: String, _ seconds: TimeInterval) -> CareAsk {
        CareAsk(askId: id, planId: "p", questionText: id, kind: .mood, short: nil, low: nil, high: nil,
                askedAt: Date(timeIntervalSince1970: seconds), status: "answered", answer: .great, answerValue: nil,
                answerScore: nil, answeredAt: nil, pushDelivered: true)
    }

    @Test func theCursorMatchesTheServersSpelling() {
        // 2026-09-30T12:30:00Z
        #expect(CareHistoryPaging.cursor(Date(timeIntervalSince1970: 1_790_771_400)) == "2026-09-30T12:30:00.000Z")
    }

    @Test func olderPagesAppendWithoutRepeats() {
        let loaded = [ask("a3", 300), ask("a2", 200)]
        let merged = CareHistoryPaging.append([ask("a2", 200), ask("a1", 100)], to: loaded)
        #expect(merged.map(\.id) == ["a3", "a2", "a1"])
    }
}

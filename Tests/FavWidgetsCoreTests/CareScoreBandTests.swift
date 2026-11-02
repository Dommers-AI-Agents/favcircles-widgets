import Testing
@testable import FavWidgetsCore

/// The traffic light for 0–10 answers (2026-11-02)
struct CareScoreBandTests {
    @Test func bands() {
        for s in 0...2 { #expect(CareScoreBand.band(for: s) == .low) }
        for s in 3...6 { #expect(CareScoreBand.band(for: s) == .middle) }
        for s in 7...10 { #expect(CareScoreBand.band(for: s) == .good) }
    }
}

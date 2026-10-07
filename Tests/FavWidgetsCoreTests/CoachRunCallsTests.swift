import Testing
import Foundation
@testable import FavWidgetsCore

struct CoachRunCallsTests {
    @Test func firstMileSaysTheTimeThenRoasts() {
        let s = CoachRunCalls.call(splits: [492], index: 0, unit: .miles, intensity: .savage, pick: { _ in 0 })
        #expect(s.hasPrefix("First mile done. 8 minutes 12."))
        #expect(s.hasSuffix(CoachRunCalls.steadySavage[0]))
    }

    @Test func slowerMileGetsCalledOut() {
        let s = CoachRunCalls.call(splits: [480, 510], index: 1, unit: .miles, intensity: .savage, pick: { _ in 0 })
        #expect(s.contains("Second mile done. 8 minutes 30."))
        #expect(s.contains("30 seconds slower than the last one."))
        #expect(s.hasSuffix(CoachRunCalls.slowerSavage[0]))
    }

    @Test func fasterMileIsFastestOfTheRun() {
        let s = CoachRunCalls.call(splits: [500, 520, 470], index: 2, unit: .miles, intensity: .clean, pick: { _ in 0 })
        #expect(s.contains("50 seconds faster than the last one."))
        #expect(s.contains("Fastest mile of the run."))
        #expect(s.hasSuffix(CoachRunCalls.fasterClean[0]))
    }

    @Test func withinFiveSecondsIsSteady() {
        let s = CoachRunCalls.call(splits: [480, 483], index: 1, unit: .miles, intensity: .clean, pick: { _ in 0 })
        #expect(s.contains("Same as the last one. Steady."))
    }

    @Test func kilometersSayKAndMark5K() {
        let s = CoachRunCalls.call(splits: [300, 300, 300, 300, 301], index: 4, unit: .kilometers, intensity: .savage, pick: { _ in 0 })
        #expect(s.hasPrefix("Fifth K done. 5 minutes 1."))
        #expect(s.contains("That's a 5K."))
    }

    @Test func outOfRangeIsSilentAndPickIsClamped() {
        #expect(CoachRunCalls.call(splits: [], index: 0, unit: .miles, intensity: .savage) == "")
        #expect(!CoachRunCalls.call(splits: [400], index: 0, unit: .miles, intensity: .savage, pick: { _ in 99 }).isEmpty)
    }

    @Test func spokenTimes() {
        #expect(CoachRunCalls.spoken(45) == "45 seconds")
        #expect(CoachRunCalls.spoken(60) == "1 minute")
        #expect(CoachRunCalls.spoken(61) == "1 minute 1")
    }

    @Test func settingsDefaultOffAndOldDocsDecode() throws {
        let old = #"{"unit":"mi"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RunSettings.self, from: old)
        #expect(!s.coachOn)
        #expect(s.coachLevel == .savage)
    }
}

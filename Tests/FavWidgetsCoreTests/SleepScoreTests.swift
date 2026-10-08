import Testing
import Foundation
@testable import FavWidgetsCore

struct SleepScoreTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    private func at(_ day: String, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: DayKey(rawValue: day).date(calendar: cal))!
    }

    @Test func aFullNightWithStagesScoresHigh() {
        let n = SleepNight(day: DayKey(rawValue: "2026-10-08"), bedtime: at("2026-10-07", 22, 45), wakeTime: at("2026-10-08", 6, 45),
                           asleepMinutes: 450, awakeMinutes: 30, deepMinutes: 80, remMinutes: 100, coreMinutes: 270, source: .health)
        let s = SleepScore.score(n, goalHours: 8, recentBedtimes: [at("2026-10-06", 22, 30), at("2026-10-05", 23)], calendar: cal)
        #expect(s.duration == 50 && s.consistency == 20 && s.stages == 10)
        #expect(s.total >= 90)
        #expect(SleepScore.label(s.total) == "Great")
    }

    @Test func shortLateNightWithoutStagesIsRescaled() {
        let n = SleepNight(day: DayKey(rawValue: "2026-10-08"), bedtime: at("2026-10-08", 2, 30), wakeTime: at("2026-10-08", 7),
                           asleepMinutes: 240, source: .manual)
        let s = SleepScore.score(n, goalHours: 8, recentBedtimes: [at("2026-10-06", 22, 30), at("2026-10-05", 22, 45), at("2026-10-04", 23)], calendar: cal)
        #expect(s.stages == nil)
        #expect(s.total < 60)
        #expect(SleepScore.bedtimeNote(n, recentBedtimes: [at("2026-10-06", 22, 30), at("2026-10-05", 22, 30), at("2026-10-04", 22, 30)], calendar: cal)
                == "To bed 4h 0m later than usual")
    }

    @Test func bedtimesAroundMidnightAreClose() {
        #expect(SleepScore.bedtimeMinutes(at("2026-10-07", 23), calendar: cal) == 660)
        #expect(SleepScore.bedtimeMinutes(at("2026-10-08", 1), calendar: cal) == 780)
    }

    @Test func samplesBecomeOneNightPerWakeDay() {
        let samples = [
            SleepSample(start: at("2026-10-07", 22, 30), end: at("2026-10-08", 6, 50), stage: .inBed),
            SleepSample(start: at("2026-10-07", 22, 50), end: at("2026-10-08", 1, 0), stage: .core),
            SleepSample(start: at("2026-10-08", 1, 0), end: at("2026-10-08", 2, 0), stage: .deep),
            SleepSample(start: at("2026-10-08", 2, 0), end: at("2026-10-08", 2, 20), stage: .awake),
            SleepSample(start: at("2026-10-08", 2, 20), end: at("2026-10-08", 4, 0), stage: .rem),
            SleepSample(start: at("2026-10-08", 4, 0), end: at("2026-10-08", 6, 30), stage: .core),
            // a 40-minute afternoon nap: dropped
            SleepSample(start: at("2026-10-08", 14), end: at("2026-10-08", 14, 40), stage: .asleep)
        ]
        let nights = SleepScore.nights(from: samples, calendar: cal)
        #expect(nights.count == 1)
        let n = nights[0]
        #expect(n.day == DayKey(rawValue: "2026-10-08"))
        #expect(n.asleepMinutes == 130 + 60 + 100 + 150)
        #expect(n.deepMinutes == 60 && n.remMinutes == 100 && n.awakeMinutes == 20)
        #expect(n.bedtime == at("2026-10-07", 22, 30))
    }

    @Test func overlappingPhoneAndWatchCountOnce() {
        let samples = [SleepSample(start: at("2026-10-07", 23), end: at("2026-10-08", 7), stage: .asleep),
                       SleepSample(start: at("2026-10-07", 23, 30), end: at("2026-10-08", 6, 30), stage: .asleep)]
        #expect(SleepScore.nights(from: samples, calendar: cal).first?.asleepMinutes == 480)
    }

    @Test func manualNightsSurviveAHealthRefresh() {
        var month = SleepMonth()
        let day = DayKey(rawValue: "2026-10-08")
        month.upsert(SleepNight(day: day, bedtime: at("2026-10-07", 23), wakeTime: at("2026-10-08", 7), asleepMinutes: 480, source: .manual))
        month.upsert(SleepNight(day: day, bedtime: at("2026-10-07", 23), wakeTime: at("2026-10-08", 6), asleepMinutes: 400, source: .health))
        #expect(month.nights.count == 1 && month.nights[0].source == .manual)
    }
}

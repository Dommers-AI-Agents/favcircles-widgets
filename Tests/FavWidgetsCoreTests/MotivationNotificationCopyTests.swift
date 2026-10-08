import Testing
@testable import FavWidgetsCore

struct MotivationNotificationCopyTests {
    @Test func theStreakIsOnTheLine() {
        #expect(MotivationNotificationCopy.subtitle(streak: 0) == "Day 1 starts now. Move.")
        #expect(MotivationNotificationCopy.subtitle(streak: 1) == "🔥 1 day down. Don't you stop now.")
        #expect(MotivationNotificationCopy.subtitle(streak: 6) == "🔥 6-day streak on the line")
    }
}

/// "Did it" counts, and the coach keeps going (Wes, 2026-10-08).
struct MotivationKeepsPushingTests {
    private let today = DayKey(rawValue: "2026-10-08")

    @Test func everyDidItCountsAndUndoTakesOneBack() {
        var log = MotivationLog()
        log.logDidIt(on: today)
        log.logDidIt(on: today)
        #expect(log.doneCount(on: today) == 2)
        #expect(log.isDone(today))
        log.undoDidIt(on: today)
        #expect(log.doneCount(on: today) == 1)
        log.undoDidIt(on: today)
        #expect(log.doneCount(on: today) == 0)
        #expect(!log.isDone(today))
    }

    @Test func aDayFromBeforeCountsExistedIsOne() {
        let log = MotivationLog(doneDays: ["2026-10-08"])
        #expect(log.doneCount(on: today) == 1)
    }

    @Test func twoPhonesKeepTheHigherCount() {
        let a = MotivationLog(doneDays: ["2026-10-08"], doneCounts: ["2026-10-08": 3])
        let b = MotivationLog(doneDays: ["2026-10-08"], doneCounts: ["2026-10-08": 1])
        #expect(MotivationLog.merge(local: b, remote: a).doneCounts["2026-10-08"] == 3)
    }

    @Test func todaysRemindersAskForOneMore() {
        #expect(MotivationNotificationCopy.subtitle(streak: 4, doneToday: 0) == "🔥 4-day streak on the line")
        #expect(MotivationNotificationCopy.subtitle(streak: 4, doneToday: 1) == "💪 1 done today. Go again.")
        #expect(MotivationNotificationCopy.subtitle(streak: 4, doneToday: 3) == "💪 3 done today. One more.")
    }
}

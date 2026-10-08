import Testing
import Foundation
@testable import FavWidgetsCore

struct MotivationTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        var d = DayKey(rawValue: day).date(calendar: calendar)
        d = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
        return d
    }

    @Test func noBankSwears() {
        // Wes 2026-10-02: no profanity anywhere, so the app needs no profanity age rating.
        let words = ["fuck", "shit", "puss", "bitch", "ass", "damn", "hell", "crap", "bastard", "dick", "piss", "bullshit"]
        for intensity in MotivationIntensity.allCases {
            for focus in MotivationFocus.allCases {
                for line in MotivationLines.bank(intensity, focus) {
                    let tokens = line.lowercased().split { !$0.isLetter }.map(String.init)
                    for word in words {
                        #expect(!tokens.contains { $0.hasPrefix(word) }, "\(line)")
                    }
                }
            }
        }
    }

    @Test func savageHasAHundredDifferentLines() {
        // Wes 2026-10-02: 100 mean lines, no curses.
        let all = MotivationLines.pool(intensity: .savage, focus: MotivationFocus.allCases)
        #expect(all.count >= 100)
        #expect(Set(all).count == all.count)
    }

    @Test func everyLineHasAStableUniqueId() {
        let all = MotivationLines.all
        let ids = all.map(MotivationLines.id(for:))
        #expect(Set(ids).count == all.count)
        for (line, id) in zip(all, ids) {
            #expect(id.count == 8 && id.allSatisfy(\.isHexDigit), "\(id)")
            #expect(MotivationLines.line(id: id) == line)
        }
        // Pinned: a changed hash would orphan every notification already scheduled.
        #expect(MotivationLines.id(for: "") == "811c9dc5")
        #expect(MotivationLines.line(id: "00000000") == nil)
    }

    @Test func shareAndChatTextCarryTheLine() {
        let line = MotivationLines.bank(.savage, .run)[0]
        #expect(MotivationShareText.shareText(line: line).contains(line))
        #expect(!MotivationShareText.shareText(line: line).contains("http"))
        #expect(MotivationShareText.chatText(line: line) == "📣 Coach Mane says: \(line)")
        #expect(MotivationLines.all.allSatisfy { $0.count <= MotivationShareText.lineLimit })
    }

    @Test func noBankUsesWordsWesRuledOut() {
        // Wes 2026-10-02: other curses are fine, not this one.
        for intensity in MotivationIntensity.allCases {
            for focus in MotivationFocus.allCases {
                for line in MotivationLines.bank(intensity, focus) {
                    #expect(!line.lowercased().contains("puss"), "\(line)")
                }
            }
        }
    }

    @Test func cleanPoolNeverPicksASavageLine() {
        let savage = Set(MotivationFocus.allCases.flatMap { MotivationLines.bank(.savage, $0) })
        let log = MotivationLog(intensity: .clean, reminders: WaterReminders(enabled: true, intervalHours: 1, startMinutes: 0, endMinutes: 23 * 60))
        for slot in MotivationPlan.slots(log, now: date("2026-10-02", 0, 0), calendar: calendar) {
            #expect(!savage.contains(slot.line))
        }
    }

    @Test func focusLimitsThePool() {
        let pool = MotivationLines.pool(intensity: .savage, focus: [.run])
        #expect(pool == MotivationLines.bank(.savage, .run))
        #expect(MotivationLines.pool(intensity: .clean, focus: []).count
                == MotivationFocus.allCases.reduce(0) { $0 + MotivationLines.bank(.clean, $1).count })
    }

    @Test func consecutiveSlotsDontRepeatUntilThePoolIsUsedUp() {
        let pool = MotivationLines.pool(intensity: .clean, focus: MotivationFocus.allCases)
        let picks = (0..<pool.count).map { MotivationLines.line(pool: pool, day: 20_000, slot: $0, slotsPerDay: pool.count) }
        #expect(Set(picks).count == pool.count)
    }

    @Test func schedulesTheRestOfTodayThenWholeDays() {
        // Every 4 h, 7:00–19:00 → 7, 11, 15, 19 = 4 slots/day → 7 days, capped.
        let log = MotivationLog(reminders: WaterReminders(enabled: true, intervalHours: 4, startMinutes: 7 * 60, endMinutes: 19 * 60))
        let slots = MotivationPlan.slots(log, now: date("2026-10-02", 12, 0), calendar: calendar)
        #expect(slots.prefix(2).map(\.minutes) == [15 * 60, 19 * 60])
        #expect(slots.prefix(2).allSatisfy { $0.day.rawValue == "2026-10-02" })
        #expect(slots[2].day.rawValue == "2026-10-03" && slots[2].minutes == 7 * 60)
        #expect(slots.count == 2 + 6 * 4)
        #expect(slots.count <= MotivationPlan.maxPending)
    }

    @Test func didItTodayKeepsTodaysRemindersComing() {
        // Wes, 2026-10-08: Did it counts progress; the coach keeps pushing
        var log = MotivationLog(reminders: WaterReminders(enabled: true, intervalHours: 4, startMinutes: 7 * 60, endMinutes: 19 * 60))
        log.logDidIt(on: DayKey(rawValue: "2026-10-02"))
        let slots = MotivationPlan.slots(log, now: date("2026-10-02", 12, 0), calendar: calendar)
        #expect(slots.first?.day.rawValue == "2026-10-02")
    }

    @Test func hourlyStaysUnderTheCap() {
        let log = MotivationLog(reminders: WaterReminders(enabled: true, intervalHours: 1, startMinutes: 0, endMinutes: 23 * 60 + 59))
        #expect(MotivationPlan.slots(log, now: date("2026-10-02", 0, 0), calendar: calendar).count <= MotivationPlan.maxPending)
        #expect(MotivationPlan.slots(MotivationLog(), now: Date(), calendar: calendar).isEmpty) // off by default
    }

    @Test func streakAndMergeKeepEveryDoneDay() {
        var a = MotivationLog()
        a.setDone(true, on: DayKey(rawValue: "2026-10-01"))
        a.setDone(true, on: DayKey(rawValue: "2026-10-02"))
        var b = MotivationLog(intensity: .savage)
        b.setDone(true, on: DayKey(rawValue: "2026-09-30"))
        let merged = MotivationLog.merge(local: a, remote: b)
        #expect(merged.intensity == .clean)
        #expect(merged.streak(endingOn: DayKey(rawValue: "2026-10-02"), calendar: calendar) == 3)
        #expect(merged.streak(endingOn: DayKey(rawValue: "2026-10-03"), calendar: calendar) == 3) // today not done yet doesn't break it
    }

    @Test func roundTripsAndOldDocumentsDecode() throws {
        var log = MotivationLog(intensity: .savage, focus: [.gym])
        log.setDone(true, on: DayKey(rawValue: "2026-10-02"))
        let data = try WidgetDocumentCodec.encode(log)
        #expect(try WidgetDocumentCodec.decode(MotivationLog.self, from: data) == log)
        let sparse = try JSONDecoder().decode(MotivationLog.self, from: Data(#"{"intensity":"nonsense"}"#.utf8))
        #expect(sparse.intensity == .clean)
        #expect(!sparse.reminders.enabled)
    }

    @Test func legendsSectionAndOlderDocs() throws {
        #expect(MotivationLines.bank(.clean, .legends).contains { $0.contains("Suffer now and live the rest of your life as a champion") })
        #expect(MotivationLines.bank(.savage, .legends).count >= 10)
        // A doc saved by an older build (no legends) still decodes, and a
        // section this build doesn't know is skipped instead of resetting the list
        let old = try JSONDecoder().decode(MotivationLog.self, from: Data(#"{"intensity":"savage","focus":["gym","someday"]}"#.utf8))
        #expect(old.focus == [.gym])
        #expect(old.intensity == .savage)
    }
}

import Testing
import Foundation
@testable import FavWidgetsCore

struct WaterReminderTests {
    @Test func oldWaterDocumentsDecodeWithRemindersOff() throws {
        let json = #"{"goalCups":10,"cupMl":300,"months":{"2026-09":[1,2,3]}}"#
        let log = try JSONDecoder().decode(WaterLog.self, from: Data(json.utf8))
        #expect(log.goalCups == 10)
        #expect(log.months[MonthKey(year: 2026, month: 9)] == [1, 2, 3])
        #expect(!log.reminders.enabled)
        #expect(log.reminders.intervalHours == 2)
    }

    @Test func everyTwoHoursFromEightToNine() {
        let r = WaterReminders(enabled: true, intervalHours: 2, startMinutes: 8 * 60, endMinutes: 21 * 60)
        #expect(WaterReminderPlan.times(r) == [480, 600, 720, 840, 960, 1080, 1200])
        #expect(WaterReminderPlan.summary(r, locale: Locale(identifier: "en_US")) == "Every 2 hours, 8:00 AM – 9:00 PM · 7 reminders")
    }

    @Test func windowShorterThanIntervalGivesJustTheStart() {
        let r = WaterReminders(enabled: true, intervalHours: 4, startMinutes: 9 * 60, endMinutes: 10 * 60)
        #expect(WaterReminderPlan.times(r) == [540])
        let flipped = WaterReminders(enabled: true, intervalHours: 1, startMinutes: 20 * 60, endMinutes: 8 * 60)
        #expect(WaterReminderPlan.times(flipped) == [1200]) // end before start → just the start
        #expect(WaterReminderPlan.summary(WaterReminders()) == "Off")
    }

    @Test func hourlyAllDayStaysUnderTheLocalNotificationCap() {
        let r = WaterReminders(enabled: true, intervalHours: 1, startMinutes: 0, endMinutes: 23 * 60 + 59)
        #expect(WaterReminderPlan.times(r).count == 24)
        #expect(WaterReminderPlan.message(index: 5, goalCups: 8) == "Sip break — a cup now keeps the streak going")
    }
}

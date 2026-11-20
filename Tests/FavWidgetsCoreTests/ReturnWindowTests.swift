import Testing
import Foundation
@testable import FavWidgetsCore

struct ReturnWindowTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    private let today = DayKey(rawValue: "2026-11-20")

    @Test func countdownAndStatusText() {
        let r = Receipt(storeName: "REI", item: "Running shoes", purchasedOn: DayKey(rawValue: "2026-11-01"), windowDays: 30)
        #expect(r.closesOn(calendar: cal) == DayKey(rawValue: "2026-12-01"))
        #expect(ReturnWindowPlan.daysLeft(r, today: today, calendar: cal) == 11)
        #expect(ReturnWindowPlan.statusText(r, today: today, calendar: cal) == "11 days left")
        #expect(ReturnWindowPlan.statusText(r, today: DayKey(rawValue: "2026-12-01"), calendar: cal) == "Last day today")
        #expect(ReturnWindowPlan.statusText(r, today: DayKey(rawValue: "2026-11-30"), calendar: cal) == "Tomorrow is the last day")
        #expect(ReturnWindowPlan.statusText(r, today: DayKey(rawValue: "2026-12-02"), calendar: cal) == "Closed yesterday")
        #expect(ReturnWindowPlan.statusText(r, today: DayKey(rawValue: "2026-12-05"), calendar: cal) == "Closed 4 days ago")
        #expect(ReturnWindowPlan.closesText(r, calendar: cal) == "Closes Dec 1")
        #expect(r.title == "Running shoes at REI")
        #expect(ReturnWindowPlan.isClosingSoon(r, today: DayKey(rawValue: "2026-11-29"), calendar: cal))
        #expect(!ReturnWindowPlan.isClosingSoon(r, today: today, calendar: cal))
    }

    @Test func openSortsSoonestAndSummaryNamesIt() {
        let shoes = Receipt(storeName: "REI", item: "Running shoes", purchasedOn: DayKey(rawValue: "2026-11-01"), windowDays: 30)
        let lamp = Receipt(storeName: "Target", item: "Lamp", purchasedOn: DayKey(rawValue: "2026-11-18"), windowDays: 90)
        var jacket = Receipt(storeName: "Costco", item: "Jacket", purchasedOn: DayKey(rawValue: "2026-10-01"), windowDays: 30)
        jacket.resolve(.returned)
        let list = [lamp, jacket, shoes]
        #expect(ReturnWindowPlan.open(list, calendar: cal).map(\.item) == ["Running shoes", "Lamp"])
        #expect(ReturnWindowPlan.resolved(list).map(\.item) == ["Jacket"])
        #expect(ReturnWindowPlan.summary(list, today: today, calendar: cal) == "2 open · Running shoes at REI, 11 days left")
        #expect(ReturnWindowPlan.summary([jacket], today: today, calendar: cal).hasPrefix("Snap a receipt"))
    }

    @Test func remindersThreeDaysBeforeAndLastMorning() {
        let r = Receipt(storeName: "REI", purchasedOn: DayKey(rawValue: "2026-11-01"), windowDays: 30)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let times = ReturnWindowPlan.reminderTimes(r, now: now, calendar: cal)
        #expect(times.map(\.id) == ["returnwindow-\(r.id)-warn", "returnwindow-\(r.id)-last"])
        #expect(cal.dateComponents([.month, .day, .hour], from: times[0].at) == DateComponents(month: 11, day: 28, hour: 9))
        #expect(cal.dateComponents([.month, .day, .hour], from: times[1].at) == DateComponents(month: 12, day: 1, hour: 9))
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 29, hour: 12))!
        #expect(ReturnWindowPlan.reminderTimes(r, now: late, calendar: cal).map(\.id) == ["returnwindow-\(r.id)-last"])
        var done = r; done.resolve(.kept)
        #expect(ReturnWindowPlan.reminderTimes(done, now: now, calendar: cal).isEmpty)
    }

    @Test func storeRemembersItsWindow() {
        var list = ReceiptList()
        #expect(list.windowDays(for: "REI") == 30)
        list.add(Receipt(storeName: "REI", purchasedOn: today, windowDays: 90))
        #expect(list.windowDays(for: " rei") == 90)
        let merged = ReceiptList.merge(local: list, remote: ReceiptList(windowByStore: ["target": 14]))
        #expect(merged.windowByStore == ["rei": 90, "target": 14])
    }
}

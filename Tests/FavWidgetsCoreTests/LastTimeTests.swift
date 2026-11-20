import Testing
import Foundation
@testable import FavWidgetsCore

struct LastTimeTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 03:20 EST
    private func days(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    @Test func elapsedTextReadsLikeAPerson() {
        #expect(LastTimePlan.elapsedText(since: nil, now: now, calendar: cal) == "Never")
        #expect(LastTimePlan.elapsedText(since: now.addingTimeInterval(-60), now: now, calendar: cal) == "Today")
        #expect(LastTimePlan.elapsedText(since: days(1), now: now, calendar: cal) == "Yesterday")
        #expect(LastTimePlan.elapsedText(since: days(6), now: now, calendar: cal) == "6 days ago")
        #expect(LastTimePlan.elapsedText(since: days(21), now: now, calendar: cal) == "3 weeks ago")
        #expect(LastTimePlan.elapsedText(since: days(70), now: now, calendar: cal) == "2 months ago")
        #expect(LastTimePlan.elapsedText(since: days(400), now: now, calendar: cal) == "1 year ago")
        #expect(LastTimePlan.shortElapsed(since: days(45), now: now, calendar: cal) == "6w")
        #expect(LastTimePlan.shortElapsed(since: nil, now: now, calendar: cal) == "never")
    }

    @Test func statusFollowsTheGap() {
        var haircut = LastTimeItem(name: "Haircut", everyDays: 42, history: [days(10)])
        #expect(LastTimePlan.status(haircut, now: now, calendar: cal) == .fine)
        haircut.history = [days(38)]
        #expect(LastTimePlan.status(haircut, now: now, calendar: cal) == .soon)
        #expect(LastTimePlan.dueText(haircut, now: now, calendar: cal) == "Due in 4 days")
        haircut.history = [days(50)]
        #expect(LastTimePlan.status(haircut, now: now, calendar: cal) == .overdue)
        #expect(LastTimePlan.dueText(haircut, now: now, calendar: cal) == "8 days overdue")
        let never = LastTimeItem(name: "Dentist", everyDays: 180)
        #expect(LastTimePlan.status(never, now: now, calendar: cal) == .overdue)
        #expect(LastTimePlan.dueText(never, now: now, calendar: cal) == "Not done yet")
        let justRemember = LastTimeItem(name: "Cleaned car", history: [days(400)])
        #expect(LastTimePlan.status(justRemember, now: now, calendar: cal) == .fine)
        #expect(LastTimePlan.dueText(justRemember, now: now, calendar: cal) == nil)
    }

    @Test func sortedPutsOverdueFirstThenLongestAgo() {
        let a = LastTimeItem(name: "Air filter", everyDays: 90, history: [days(100)])
        let b = LastTimeItem(name: "Haircut", everyDays: 42, history: [days(10)])
        let c = LastTimeItem(name: "Called Mom", history: [days(30)])
        let d = LastTimeItem(name: "Plants", everyDays: 7, history: [days(6)])
        let names = LastTimePlan.sorted([b, c, d, a], now: now, calendar: cal).map(\.name)
        #expect(names == ["Air filter", "Plants", "Called Mom", "Haircut"])
        #expect(LastTimePlan.summary([a, b], now: now, calendar: cal) == "1 overdue · Air filter 3 months ago")
        #expect(LastTimePlan.summary([b], now: now, calendar: cal) == "All caught up · Haircut 10 days ago")
    }

    @Test func didItAndUndoAndReminder() {
        var item = LastTimeItem(name: "Haircut", everyDays: 42)
        item.markDone(at: days(2))
        item.markDone(at: now)
        #expect(item.history.count == 2 && item.lastDone == now)
        item.undoLast(now: now)
        #expect(item.lastDone == days(2))
        let at = LastTimePlan.reminderTime(item, now: now, calendar: cal)!
        #expect(cal.component(.hour, from: at) == 9)
        #expect(cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: at)).day == 40)
        #expect(LastTimePlan.reminderTime(LastTimeItem(name: "x", everyDays: 7, history: [days(30)]), now: now, calendar: cal) == nil)
    }

    @Test func mergeKeepsEveryDidItFromBothPhones() {
        var local = LastTimeItem(id: "h", name: "Haircut", history: [days(50)])
        var remote = local
        local.markDone(at: days(2)); remote.markDone(at: days(1))
        let merged = LastTimeList.merge(local: LastTimeList(items: [local]), remote: LastTimeList(items: [remote, LastTimeItem(id: "n", name: "New")]))
        #expect(merged.items.count == 2)
        #expect(merged.items.first { $0.id == "h" }?.history == [days(50), days(2), days(1)])
    }
}

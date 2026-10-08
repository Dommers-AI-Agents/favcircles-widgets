import Testing
import Foundation
@testable import FavWidgetsCore

struct MedPlanTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    private func at(_ day: String, _ h: Int, _ m: Int = 0) -> Date {
        let d = DayKey(rawValue: day).date(calendar: cal)
        return cal.date(bySettingHour: h, minute: m, second: 0, of: d)!
    }
    private let lisinopril = Med(id: "l", name: "Lisinopril", dose: "10 mg", times: [8 * 60, 20 * 60])
    private let weekly = Med(id: "w", name: "Vitamin D", times: [9 * 60], days: [2]) // Mondays

    @Test func slotsFollowTimesAndWeekdays() {
        // 2026-10-12 is a Monday
        let monday = MedPlan.slots([lisinopril, weekly], on: DayKey(rawValue: "2026-10-12"), calendar: cal)
        #expect(monday.map(\.minutes) == [480, 540, 1200])
        let tuesday = MedPlan.slots([lisinopril, weekly], on: DayKey(rawValue: "2026-10-13"), calendar: cal)
        #expect(tuesday.map(\.med.id) == ["l", "l"])
    }

    @Test func statesOverTheDay() {
        let day = DayKey(rawValue: "2026-10-12")
        let morning = MedPlan.slots([lisinopril], on: day, calendar: cal)[0]
        #expect(MedPlan.state(morning, doses: [], now: at("2026-10-12", 7, 0)) == .upcoming)
        #expect(MedPlan.state(morning, doses: [], now: at("2026-10-12", 7, 45)) == .due)
        #expect(MedPlan.state(morning, doses: [], now: at("2026-10-12", 9, 59)) == .due)
        #expect(MedPlan.state(morning, doses: [], now: at("2026-10-12", 10, 0)) == .missed)
        let taken = MedDose(medId: "l", day: day, slot: 480, status: .taken, at: at("2026-10-12", 8, 5))
        #expect(MedPlan.state(morning, doses: [taken], now: at("2026-10-12", 12)) == .taken)
    }

    @Test func nextDoseAndAdherence() {
        let day = DayKey(rawValue: "2026-10-12")
        let taken = MedDose(medId: "l", day: day, slot: 480, status: .taken, at: at("2026-10-12", 8))
        #expect(MedPlan.next([lisinopril], doses: [taken], now: at("2026-10-12", 9), calendar: cal)?.minutes == 1200)
        // after the evening dose's window: tomorrow morning
        let next = MedPlan.next([lisinopril], doses: [taken], now: at("2026-10-12", 23), calendar: cal)
        #expect(next?.day == DayKey(rawValue: "2026-10-13") && next?.minutes == 480)
        // 1 of 2 due today taken; the evening one is past due
        #expect(MedPlan.adherence([lisinopril], doses: [taken], days: 1, now: at("2026-10-12", 21), calendar: cal) == 0.5)
        #expect(MedPlan.adherence([lisinopril], doses: [], days: 1, now: at("2026-10-12", 7), calendar: cal) == nil)
    }

    @Test func remindersCapAt60() {
        let one = MedPlan.reminders([lisinopril, weekly])
        #expect(one.reminders.map(\.id) == ["med-l-480", "med-w-540-2", "med-l-1200"])
        #expect(one.dropped == 0)
        let many = (0..<10).map { Med(id: "m\($0)", name: "M\($0)", times: [60, 120], days: [1, 2, 3, 4, 5]) }
        let capped = MedPlan.reminders(many)
        #expect(capped.reminders.count == 60 && capped.dropped == 40)
    }

    @Test func monthsMergeKeepingTheNewerMark() {
        let day = DayKey(rawValue: "2026-10-12")
        let a = MedMonth(doses: [MedDose(medId: "l", day: day, slot: 480, status: .skipped, at: at("2026-10-12", 8))])
        let b = MedMonth(doses: [MedDose(medId: "l", day: day, slot: 480, status: .taken, at: at("2026-10-12", 9)),
                                 MedDose(medId: "l", day: day, slot: 1200, status: .taken, at: at("2026-10-12", 20))])
        let merged = MedMonth.merge(local: a, remote: b)
        #expect(merged.doses.count == 2)
        #expect(merged.doses.first { $0.slot == 480 }?.status == .taken)
    }

    @Test func quickLogWritesTheMonthShardAndRetriesOnConflict() async throws {
        let store = InMemoryWidgetDataStore()
        let now = at("2026-10-12", 8, 2)
        try await MedQuickLog.markTaken(store: store, medId: "l", slot: 480, now: now, calendar: cal)
        let doc = try #require(store.document(id: "meds_2026-10"))
        let month = try WidgetDocumentCodec.decode(MedMonth.self, from: doc.payload)
        #expect(month.doses.map(\.status) == [.taken])
        // marking the evening one too keeps both
        try await MedQuickLog.markTaken(store: store, medId: "l", slot: 1200, now: at("2026-10-12", 20), calendar: cal)
        let again = try WidgetDocumentCodec.decode(MedMonth.self, from: try #require(store.document(id: "meds_2026-10")).payload)
        #expect(again.doses.count == 2)
    }
}

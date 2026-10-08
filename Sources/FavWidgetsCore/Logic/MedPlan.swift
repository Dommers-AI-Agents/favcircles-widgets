import Foundation

/// Which doses are due, taken or missed; adherence; and the reminder
/// schedule. Pure so it's tested.
public enum MedPlan {
    /// A dose with no mark this long after its time counts as missed.
    public static let missedAfter: TimeInterval = 2 * 60 * 60
    /// Shown as "due" from this long before its time.
    public static let dueBefore: TimeInterval = 30 * 60
    /// iOS keeps 64 pending notifications per app; leave room for others.
    public static let maxReminders = 60

    public enum State: Equatable, Sendable { case upcoming, due, taken, skipped, missed }

    public struct Slot: Equatable, Identifiable, Sendable {
        public let med: Med
        public let day: DayKey
        public let minutes: Int
        public let dueAt: Date
        public var id: String { MedDose.key(medId: med.id, day: day, slot: minutes) }
    }

    /// Every dose scheduled on `day`, in time order.
    public static func slots(_ meds: [Med], on day: DayKey, calendar: Calendar = .current) -> [Slot] {
        let weekday = day.weekday(calendar: calendar)
        let start = calendar.startOfDay(for: day.date(calendar: calendar))
        return meds.filter { $0.active && $0.isScheduled(onWeekday: weekday) }
            .flatMap { med in med.times.map { m in
                Slot(med: med, day: day, minutes: m, dueAt: start.addingTimeInterval(TimeInterval(m * 60)))
            } }
            .sorted { ($0.minutes, $0.med.name) < ($1.minutes, $1.med.name) }
    }

    public static func state(_ slot: Slot, doses: [MedDose], now: Date) -> State {
        if let mark = doses.first(where: { $0.id == slot.id }) { return mark.status == .taken ? .taken : .skipped }
        if now >= slot.dueAt.addingTimeInterval(missedAfter) { return .missed }
        if now >= slot.dueAt.addingTimeInterval(-dueBefore) { return .due }
        return .upcoming
    }

    /// The next dose still to take: today's due/upcoming ones first, then tomorrow's first.
    public static func next(_ meds: [Med], doses: [MedDose], now: Date, calendar: Calendar = .current) -> Slot? {
        let today = DayKey(now, calendar: calendar)
        if let s = slots(meds, on: today, calendar: calendar).first(where: {
            [.due, .upcoming].contains(state($0, doses: doses, now: now))
        }) { return s }
        for offset in 1...7 {
            if let s = slots(meds, on: today.adding(days: offset, calendar: calendar), calendar: calendar).first { return s }
        }
        return nil
    }

    /// Taken ÷ doses that were due, over the `days` days ending today
    /// (doses not yet due today don't count). nil with nothing due.
    public static func adherence(_ meds: [Med], doses: [MedDose], days: Int, now: Date, calendar: Calendar = .current) -> Double? {
        let today = DayKey(now, calendar: calendar)
        var due = 0, taken = 0
        for offset in 0..<max(days, 1) {
            for slot in slots(meds, on: today.adding(days: -offset, calendar: calendar), calendar: calendar) where slot.dueAt <= now {
                due += 1
                if state(slot, doses: doses, now: now) == .taken { taken += 1 }
            }
        }
        return due == 0 ? nil : Double(taken) / Double(due)
    }

    /// One repeating reminder: every day at `minutes`, or weekly on `weekday`.
    public struct Reminder: Equatable, Sendable {
        public let id: String
        public let medId: String
        public let minutes: Int
        public let weekday: Int?
        public let title: String
        public let body: String
    }

    /// The reminders to schedule, capped at `maxReminders`; `dropped` > 0
    /// means some didn't fit (the screen says so).
    public static func reminders(_ meds: [Med]) -> (reminders: [Reminder], dropped: Int) {
        var all: [Reminder] = []
        for med in meds where med.active {
            for m in med.times {
                let body = med.note.isEmpty ? "Time for \(med.label)." : "Time for \(med.label). \(med.note)"
                if med.days.isEmpty {
                    all.append(Reminder(id: "med-\(med.id)-\(m)", medId: med.id, minutes: m, weekday: nil, title: "💊 \(med.name)", body: body))
                } else {
                    for d in med.days {
                        all.append(Reminder(id: "med-\(med.id)-\(m)-\(d)", medId: med.id, minutes: m, weekday: d, title: "💊 \(med.name)", body: body))
                    }
                }
            }
        }
        all.sort { ($0.minutes, $0.id) < ($1.minutes, $1.id) }
        return (Array(all.prefix(maxReminders)), max(0, all.count - maxReminders))
    }

    /// "8:00 AM"
    public static func timeText(_ minutes: Int, calendar: Calendar = .current) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let date = calendar.date(from: c) ?? Date()
        let f = DateFormatter(); f.locale = calendar.locale ?? .current; f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}

/// "Took it" from the reminder itself, with no widget on screen (the app's
/// notification action handler calls this, like WaterQuickLog).
public enum MedQuickLog {
    public static let widgetId = "meds"
    public static let categoryIdentifier = "MED_REMINDER"
    public static let takenAction = "MED_TAKEN"
    public static let snoozeAction = "MED_SNOOZE"
    public static let notificationType = "med_reminder"

    /// Marks today's (or `day`'s) dose of `medId` at `slot` taken.
    @discardableResult
    public static func markTaken(store: WidgetDataStore, medId: String, slot: Int, day: DayKey? = nil,
                                 now: Date = Date(), calendar: Calendar = .current) async throws -> MedDose {
        let day = day ?? DayKey(now, calendar: calendar)
        let id = WidgetShardPlanner.shardId(widgetId: widgetId, month: day.monthKey)
        let dose = MedDose(medId: medId, day: day, slot: slot, status: .taken, at: now)
        var document = try await store.load(id: id)
        for attempt in 0..<2 {
            var month = try document.map { try WidgetDocumentCodec.decode(MedMonth.self, from: $0.payload) } ?? MedMonth()
            month.record(dose)
            let next = WidgetDocument(version: document?.version ?? 0, payload: try WidgetDocumentCodec.encode(month),
                                      schemaVersion: MedSettings.schemaVersion)
            do {
                _ = try await store.save(id: id, document: next)
                return dose
            } catch WidgetDataStoreError.conflict(let server) where attempt == 0 {
                if let server { document = server } else { document = try await store.load(id: id) }
            }
        }
        throw WidgetDataStoreError.conflict(server: nil)
    }
}

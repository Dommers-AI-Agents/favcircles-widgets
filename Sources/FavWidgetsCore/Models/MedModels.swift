import Foundation

/// Medication reminders (Wes, 2026-10-08): private to the person — reminders
/// on this phone and a log of doses. Settings are one small document; the
/// log is sharded by month (`meds_YYYY-MM`) and never pruned.
public struct MedSettings: WidgetModel {
    public static let schemaVersion = 1
    public var meds: [Med]
    public init(meds: [Med] = []) { self.meds = meds }
    public static let empty = MedSettings()

    public var activeMeds: [Med] { meds.filter(\.active) }
}

public struct Med: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// "10 mg", "2 pills" — free text
    public var dose: String
    /// Minutes after midnight, sorted
    public var times: [Int]
    /// 1 = Sunday … 7 = Saturday; empty = every day
    public var days: [Int]
    public var note: String
    public var active: Bool

    public init(id: String = UUID().uuidString, name: String, dose: String = "", times: [Int] = [8 * 60],
                days: [Int] = [], note: String = "", active: Bool = true) {
        self.id = id; self.name = name; self.dose = dose; self.times = times.sorted()
        self.days = days.sorted(); self.note = note; self.active = active
    }

    public func isScheduled(onWeekday weekday: Int) -> Bool { days.isEmpty || days.contains(weekday) }

    /// "Lisinopril 10 mg"
    public var label: String { dose.isEmpty ? name : "\(name) \(dose)" }
}

public enum MedDoseStatus: String, Codable, Sendable { case taken, skipped }

/// One logged dose. `id` = medId|day|slot, so marking twice is one entry.
public struct MedDose: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let medId: String
    public let day: DayKey
    public let slot: Int
    public var status: MedDoseStatus
    public var at: Date

    public init(medId: String, day: DayKey, slot: Int, status: MedDoseStatus, at: Date) {
        self.id = MedDose.key(medId: medId, day: day, slot: slot)
        self.medId = medId; self.day = day; self.slot = slot; self.status = status; self.at = at
    }

    public static func key(medId: String, day: DayKey, slot: Int) -> String { "\(medId)|\(day.rawValue)|\(slot)" }
}

/// One month of logged doses.
public struct MedMonth: WidgetModel {
    public var doses: [MedDose]
    public init(doses: [MedDose] = []) { self.doses = doses }
    public static let empty = MedMonth()

    /// Records (or replaces) a dose.
    public mutating func record(_ dose: MedDose) {
        doses.removeAll { $0.id == dose.id }
        doses.append(dose)
    }

    public mutating func remove(id: String) { doses.removeAll { $0.id == id } }

    /// Two phones logging: keep everything; the same dose keeps the newer mark.
    public static func merge(local: MedMonth, remote: MedMonth) -> MedMonth {
        var byId: [String: MedDose] = [:]
        for d in remote.doses + local.doses {
            if let existing = byId[d.id], existing.at > d.at { continue }
            byId[d.id] = d
        }
        return MedMonth(doses: byId.values.sorted { $0.at < $1.at })
    }
}

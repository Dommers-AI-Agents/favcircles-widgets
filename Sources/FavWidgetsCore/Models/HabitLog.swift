import Foundation

public enum HabitSchedule: Codable, Equatable, Hashable, Sendable {
    case daily
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday).
    case weekdays(Set<Int>)

    public func isDue(on day: DayKey, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily: return true
        case .weekdays(let days): return days.contains(day.weekday(calendar: calendar))
        }
    }
}

public struct Habit: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var schedule: HabitSchedule
    public var createdAt: Date
    /// Archived habits leave the daily list but keep their history.
    public var archivedAt: Date?

    public init(id: UUID = UUID(), name: String, symbolName: String = "checkmark.circle",
                schedule: HabitSchedule = .daily, createdAt: Date = Date(), archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.schedule = schedule
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

/// Single document for all time. Completions are one character per day per
/// month ("1" done, "0" not), so five habits for ten years is ~20 KB.
/// Keyed by the habit id's uuidString so the JSON is a plain object.
public struct HabitLog: WidgetModel {
    public var habits: [Habit]
    public var completions: [String: [MonthKey: String]]

    public init(habits: [Habit] = [], completions: [String: [MonthKey: String]] = [:]) {
        self.habits = habits
        self.completions = completions
    }

    public static let empty = HabitLog()

    public var activeHabits: [Habit] { habits.filter { !$0.isArchived } }

    public func isDone(_ habitId: UUID, on day: DayKey) -> Bool {
        guard let bits = completions[habitId.uuidString]?[day.monthKey] else { return false }
        let index = day.day - 1
        guard index >= 0, index < bits.count else { return false }
        return bits[bits.index(bits.startIndex, offsetBy: index)] == "1"
    }

    public mutating func setDone(_ done: Bool, habitId: UUID, on day: DayKey, calendar: Calendar = .current) {
        let month = day.monthKey
        var bits = Array(completions[habitId.uuidString]?[month] ?? "")
        let needed = max(bits.count, month.dayCount(calendar: calendar), day.day)
        if bits.count < needed { bits.append(contentsOf: Array(repeating: Character("0"), count: needed - bits.count)) }
        bits[day.day - 1] = done ? "1" : "0"
        completions[habitId.uuidString, default: [:]][month] = String(bits)
    }

    public mutating func toggle(_ habitId: UUID, on day: DayKey, calendar: Calendar = .current) {
        setDone(!isDone(habitId, on: day), habitId: habitId, on: day, calendar: calendar)
    }

    public func doneCount(on day: DayKey, calendar: Calendar = .current) -> (done: Int, due: Int) {
        let due = activeHabits.filter { $0.schedule.isDue(on: day, calendar: calendar) }
        return (due.filter { isDone($0.id, on: day) }.count, due.count)
    }

    /// Bitwise OR: a completion recorded on either device stands.
    public static func merge(local: HabitLog, remote: HabitLog) -> HabitLog {
        var merged = local
        let knownHabits = Set(local.habits.map(\.id))
        merged.habits.append(contentsOf: remote.habits.filter { !knownHabits.contains($0.id) })
        for (habitId, remoteMonths) in remote.completions {
            for (month, remoteBits) in remoteMonths {
                let localBits = Array(merged.completions[habitId]?[month] ?? "")
                let remoteArray = Array(remoteBits)
                let length = max(localBits.count, remoteArray.count)
                var out: [Character] = []
                out.reserveCapacity(length)
                for i in 0..<length {
                    let l = i < localBits.count && localBits[i] == "1"
                    let r = i < remoteArray.count && remoteArray[i] == "1"
                    out.append(l || r ? "1" : "0")
                }
                merged.completions[habitId, default: [:]][month] = String(out)
            }
        }
        return merged
    }
}

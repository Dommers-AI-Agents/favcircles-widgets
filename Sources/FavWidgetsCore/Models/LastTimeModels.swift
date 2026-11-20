import Foundation

/// Last Time (Wes, 2026-11-20): things nobody tracks but everybody wonders
/// about — haircut, air filter, called Mom. One tap says "did it"; the tile
/// shows how long it has been and turns amber when it is due. One document;
/// every "did it" is kept (never pruned).
public struct LastTimeList: WidgetModel {
    public static let schemaVersion = 1
    public var items: [LastTimeItem]
    public init(items: [LastTimeItem] = []) { self.items = items }
    public static let empty = LastTimeList()

    /// Two phones: union by id; the same item keeps the later edit and the
    /// union of both histories, so a "did it" logged on either phone stays.
    public static func merge(local: LastTimeList, remote: LastTimeList) -> LastTimeList {
        var byId = Dictionary(remote.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in local.items {
            if let r = byId[item.id] {
                var kept = r.updatedAt > item.updatedAt ? r : item
                kept.history = Array(Set(r.history).union(item.history)).sorted()
                byId[item.id] = kept
            } else {
                byId[item.id] = item
            }
        }
        return LastTimeList(items: byId.values.sorted { $0.createdAt < $1.createdAt })
    }
}

public struct LastTimeItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var symbolName: String
    /// Expected gap in days; nil = just remember, never nag.
    public var everyDays: Int?
    /// Every time it was done, oldest first.
    public var history: [Date]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, name: String, symbolName: String = "clock.arrow.circlepath",
                everyDays: Int? = nil, history: [Date] = [], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.symbolName = symbolName; self.everyDays = everyDays
        self.history = history.sorted(); self.createdAt = createdAt; self.updatedAt = createdAt
    }

    public var lastDone: Date? { history.last }

    /// Logs a "did it" now (the newest entry is also what Undo removes).
    public mutating func markDone(at date: Date = Date()) {
        history.append(date)
        history.sort()
        updatedAt = date
    }

    /// Removes the newest entry (Undo).
    public mutating func undoLast(now: Date = Date()) {
        guard !history.isEmpty else { return }
        history.removeLast()
        updatedAt = now
    }

    /// When it is next expected, from the last time and the gap.
    public var dueDate: Date? {
        guard let last = lastDone, let every = everyDays else { return nil }
        return last.addingTimeInterval(TimeInterval(every) * 86_400)
    }
}

public enum LastTimePlan {
    public enum Status: Equatable, Sendable {
        /// No expectation set, or well inside the gap.
        case fine
        /// Within a week (or a seventh of the gap) of being due.
        case soon
        /// Past the gap, or never done when a gap is set.
        case overdue
    }

    /// "Never" / "Today" / "Yesterday" / "6 days ago" / "3 weeks ago" / "2 months ago" / "1 year ago"
    public static func elapsedText(since last: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let last else { return "Never" }
        let days = elapsedDays(since: last, now: now, calendar: calendar)
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        case 60..<365: return "\(days / 30) months ago"
        default:
            let years = days / 365
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
    }

    /// Short form for a chip: "6d" / "3w" / "2mo" / "1y" / "never"
    public static func shortElapsed(since last: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let last else { return "never" }
        let days = elapsedDays(since: last, now: now, calendar: calendar)
        switch days {
        case ..<1: return "today"
        case 1..<14: return "\(days)d"
        case 14..<60: return "\(days / 7)w"
        case 60..<365: return "\(days / 30)mo"
        default: return "\(days / 365)y"
        }
    }

    /// Whole calendar days between the two dates.
    public static func elapsedDays(since last: Date, now: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: last), b = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    public static func status(_ item: LastTimeItem, now: Date, calendar: Calendar = .current) -> Status {
        guard let every = item.everyDays else { return .fine }
        guard let last = item.lastDone else { return .overdue }
        let days = elapsedDays(since: last, now: now, calendar: calendar)
        if days >= every { return .overdue }
        let lead = max(1, min(7, every / 7))
        return days >= every - lead ? .soon : .fine
    }

    /// "Due in 4 days" / "Due today" / "5 days overdue"; nil without a gap.
    public static func dueText(_ item: LastTimeItem, now: Date, calendar: Calendar = .current) -> String? {
        guard let every = item.everyDays else { return nil }
        guard let last = item.lastDone else { return "Not done yet" }
        let left = every - elapsedDays(since: last, now: now, calendar: calendar)
        if left > 1 { return "Due in \(left) days" }
        if left == 1 { return "Due tomorrow" }
        if left == 0 { return "Due today" }
        return -left == 1 ? "1 day overdue" : "\(-left) days overdue"
    }

    /// Most overdue first, then due soon, then the longest-ago; ties by name.
    public static func sorted(_ items: [LastTimeItem], now: Date, calendar: Calendar = .current) -> [LastTimeItem] {
        func rank(_ s: Status) -> Int { s == .overdue ? 0 : (s == .soon ? 1 : 2) }
        return items.sorted { a, b in
            let ra = rank(status(a, now: now, calendar: calendar)), rb = rank(status(b, now: now, calendar: calendar))
            if ra != rb { return ra < rb }
            let da = a.lastDone.map { elapsedDays(since: $0, now: now, calendar: calendar) } ?? Int.max
            let db = b.lastDone.map { elapsedDays(since: $0, now: now, calendar: calendar) } ?? Int.max
            if da != db { return da > db }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// "2 overdue · Haircut 7 weeks ago" — the card's one line.
    public static func summary(_ items: [LastTimeItem], now: Date, calendar: Calendar = .current) -> String {
        guard !items.isEmpty else { return "Add the things you always wonder about" }
        let ordered = sorted(items, now: now, calendar: calendar)
        let overdue = items.filter { status($0, now: now, calendar: calendar) == .overdue }.count
        let lead = ordered[0]
        let leadText = "\(lead.name) \(elapsedText(since: lead.lastDone, now: now, calendar: calendar).lowercased())"
        if overdue > 0 { return "\(overdue) overdue · \(leadText)" }
        return "All caught up · \(leadText)"
    }

    /// 9 AM on the day it comes due, when that is still ahead.
    public static func reminderTime(_ item: LastTimeItem, now: Date, calendar: Calendar = .current) -> Date? {
        guard let due = item.dueDate else { return nil }
        guard let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due), at > now else { return nil }
        return at
    }

    public struct Starter: Equatable, Sendable {
        public let name: String
        public let symbolName: String
        public let everyDays: Int?
    }

    /// One-tap suggestions on the add sheet (never seeded as data).
    public static let starters: [Starter] = [
        Starter(name: "Haircut", symbolName: "scissors", everyDays: 42),
        Starter(name: "Air filter", symbolName: "wind", everyDays: 90),
        Starter(name: "Oil change", symbolName: "car.fill", everyDays: 180),
        Starter(name: "Called Mom", symbolName: "phone.fill", everyDays: 7),
        Starter(name: "Watered plants", symbolName: "leaf.fill", everyDays: 7),
        Starter(name: "Smoke alarm batteries", symbolName: "flame.fill", everyDays: 180),
        Starter(name: "Dentist", symbolName: "mouth.fill", everyDays: 180),
        Starter(name: "Changed sheets", symbolName: "bed.double.fill", everyDays: 14),
        Starter(name: "Flea meds", symbolName: "pawprint.fill", everyDays: 30),
        Starter(name: "Backed up phone", symbolName: "externaldrive.fill", everyDays: 30),
        Starter(name: "Date night", symbolName: "heart.fill", everyDays: 14),
        Starter(name: "Cleaned the car", symbolName: "sparkles", everyDays: nil)
    ]

    /// Symbols the editor offers for a custom item.
    public static let symbolChoices = [
        "clock.arrow.circlepath", "scissors", "wind", "car.fill", "phone.fill", "leaf.fill", "flame.fill", "mouth.fill",
        "bed.double.fill", "pawprint.fill", "externaldrive.fill", "heart.fill", "sparkles", "wrench.fill", "house.fill",
        "cross.case.fill", "drop.fill", "trash.fill", "cart.fill", "figure.walk", "book.fill", "gift.fill"
    ]

    /// The gap choices on the editor; nil = no expectation.
    public static let gapChoices: [Int?] = [nil, 7, 14, 30, 42, 60, 90, 180, 365]

    public static func gapTitle(_ days: Int?) -> String {
        guard let days else { return "No reminder" }
        switch days {
        case 7: return "Every week"
        case 14: return "Every 2 weeks"
        case 30: return "Every month"
        case 42: return "Every 6 weeks"
        case 60: return "Every 2 months"
        case 90: return "Every 3 months"
        case 180: return "Every 6 months"
        case 365: return "Every year"
        default: return "Every \(days) days"
        }
    }
}

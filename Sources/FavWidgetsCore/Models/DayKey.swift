import Foundation

/// Lets `DayKey`/`MonthKey` act as JSON object keys. Without this, Swift
/// encodes `[DayKey: T]` as a flat array of alternating keys and values.
struct WidgetStringCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A calendar day as "yyyy-MM-dd" in the user's calendar. String-backed so
/// it is a stable JSON dictionary key.
public struct DayKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible, CodingKeyRepresentable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func today(calendar: Calendar = .current) -> DayKey {
        DayKey(Date(), calendar: calendar)
    }

    public var year: Int { Int(rawValue.prefix(4)) ?? 0 }
    public var month: Int { Int(rawValue.dropFirst(5).prefix(2)) ?? 0 }
    public var day: Int { Int(rawValue.suffix(2)) ?? 0 }
    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(), calendar: calendar)
    }

    /// 1 = Sunday … 7 = Saturday (Calendar's weekday numbering).
    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date(calendar: calendar))
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }

    public var codingKey: CodingKey { WidgetStringCodingKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// A calendar month as "yyyy-MM"; the key for monthly shards and compact
/// per-month arrays.
public struct MonthKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible, CodingKeyRepresentable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(year: Int, month: Int) {
        rawValue = String(format: "%04d-%02d", year, month)
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0)
    }

    public static func current(calendar: Calendar = .current) -> MonthKey {
        MonthKey(Date(), calendar: calendar)
    }

    public var year: Int { Int(rawValue.prefix(4)) ?? 0 }
    public var month: Int { Int(rawValue.suffix(2)) ?? 0 }

    public var previous: MonthKey {
        month == 1 ? MonthKey(year: year - 1, month: 12) : MonthKey(year: year, month: month - 1)
    }

    public var next: MonthKey {
        month == 12 ? MonthKey(year: year + 1, month: 1) : MonthKey(year: year, month: month + 1)
    }

    public func dayCount(calendar: Calendar = .current) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    public func day(_ day: Int) -> DayKey {
        DayKey(rawValue: String(format: "%@-%02d", rawValue, day))
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }

    public var codingKey: CodingKey { WidgetStringCodingKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

import Foundation

/// Recent Contacts (Wes, 2026-10-09): the last 50 people added to the phone's
/// contacts, newest first. Read on the phone and never uploaded or stored —
/// the widget has no document.
///
/// When a contact was added comes from the system's own "first saved" date
/// (the AddressBook creation date; Contacts has no public equivalent). Many
/// contacts brought over from an old phone or iCloud share one date, so a
/// block of them reads as imported together rather than as a busy afternoon.
public struct RecentContact: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let organization: String?
    public let phone: String?
    public let email: String?
    public let addedAt: Date
    public let thumbnail: Data?

    public init(id: String, name: String, organization: String? = nil, phone: String? = nil,
                email: String? = nil, addedAt: Date, thumbnail: Data? = nil) {
        self.id = id
        self.name = name
        self.organization = organization
        self.phone = phone
        self.email = email
        self.addedAt = addedAt
        self.thumbnail = thumbnail
    }

    /// "JD" for the avatar when there's no photo.
    public var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

public enum RecentContacts {
    public static let limit = 50
    /// This many contacts sharing one minute = an import or sync, not people met.
    public static let importThreshold = 10

    /// Newest first; ties by name so the order is stable.
    public static func latest(_ all: [RecentContact], limit: Int = limit) -> [RecentContact] {
        Array(all.sorted { $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt
                                                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(limit))
    }

    public struct Section: Equatable, Sendable {
        public let title: String
        public let contacts: [RecentContact]
    }

    /// Today, Yesterday, This week, This month, then one section per month.
    public static func sections(_ contacts: [RecentContact], now: Date = Date(), calendar: Calendar = .current) -> [Section] {
        var order: [String] = []
        var buckets: [String: [RecentContact]] = [:]
        for contact in contacts {
            let title = bucket(contact.addedAt, now: now, calendar: calendar)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(contact)
        }
        return order.map { Section(title: $0, contacts: buckets[$0] ?? []) }
    }

    static func bucket(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= weekAgo { return "This week" }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return "This month" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMM" : "MMMM yyyy"
        return f.string(from: date)
    }

    /// The row's date line: "Added 3:14 PM", "Added yesterday", "Added Tue",
    /// "Added Mar 3", "Added Mar 3, 2024".
    public static func addedText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateFormat = "h:mm a"
            return "Added \(f.string(from: date))"
        }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Added yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), date >= weekAgo {
            f.dateFormat = "EEEE"
            return "Added \(f.string(from: date))"
        }
        f.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return "Added \(f.string(from: date))"
    }

    /// Minutes in which `importThreshold`+ contacts were saved at once.
    public static func importedMinutes(_ contacts: [RecentContact]) -> Set<Int> {
        let minutes = contacts.map { Int($0.addedAt.timeIntervalSince1970 / 60) }
        let counts = Dictionary(minutes.map { ($0, 1) }, uniquingKeysWith: +)
        return Set(counts.filter { $0.value >= importThreshold }.keys)
    }

    public static func isImported(_ contact: RecentContact, in minutes: Set<Int>) -> Bool {
        minutes.contains(Int(contact.addedAt.timeIntervalSince1970 / 60))
    }

    /// The home card: "Added today: Jane Doe" / "3 new this week · latest Jane Doe".
    public static func cardSummary(_ contacts: [RecentContact], now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let newest = contacts.first else { return "No contacts yet" }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thisWeek = contacts.filter { $0.addedAt >= weekAgo }.count
        if calendar.isDate(newest.addedAt, inSameDayAs: now), thisWeek <= 1 { return "Added today: \(newest.name)" }
        if thisWeek > 1 { return "\(thisWeek) new this week · latest \(newest.name)" }
        return "Latest: \(newest.name) · \(addedText(newest.addedAt, now: now, calendar: calendar).replacingOccurrences(of: "Added ", with: ""))"
    }

    /// A display name from the parts a contact may have.
    public static func displayName(first: String?, last: String?, organization: String?, phone: String?, email: String?) -> String {
        let name = [first, last].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        for fallback in [organization, email, phone] {
            if let f = fallback?.trimmingCharacters(in: .whitespaces), !f.isEmpty { return f }
        }
        return "No name"
    }

    /// Digits only, for tel:/sms: links ("+1 (704) 555-0100" → "+17045550100").
    public static func dialable(_ phone: String) -> String {
        var out = ""
        for (i, ch) in phone.enumerated() where ch.isNumber || (ch == "+" && i == 0) { out.append(ch) }
        return out
    }
}

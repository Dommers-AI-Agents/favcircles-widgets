import Foundation

/// Calendar days as "YYYY-MM-DD" (birthdays, vaccine dates): no time, no
/// zone, read in whatever calendar the phone uses.
public enum DogDay {
    /// "2024-03-05" → itself; "2024-3-5" or "2024-03-05T00:00:00Z" → "2024-03-05"; junk → nil.
    public static func normalized(_ text: String) -> String? {
        let head = text.trimmingCharacters(in: .whitespaces).split(separator: "T").first.map(String.init) ?? ""
        let raw = head.split(separator: "-", omittingEmptySubsequences: false)
        let parts = raw.compactMap { Int($0) }
        guard raw.count == 3, parts.count == 3, (1900...2200).contains(parts[0]), (1...12).contains(parts[1]),
              (1...31).contains(parts[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
    }

    public static func components(_ day: String) -> DateComponents? {
        guard let n = normalized(day) else { return nil }
        let p = n.split(separator: "-").compactMap { Int($0) }
        return DateComponents(year: p[0], month: p[1], day: p[2])
    }

    /// Midnight of that day in `calendar`.
    public static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        components(day).flatMap { calendar.date(from: $0) }
    }

    public static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    /// "Mar 5, 2024"
    public static func display(_ day: String?, calendar: Calendar = .current) -> String? {
        guard let day, let date = date(day, calendar: calendar) else { return nil }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    /// Whole days from `from`'s day to `day` (negative = in the past).
    public static func daysUntil(_ day: String, from: Date, calendar: Calendar = .current) -> Int? {
        guard let target = date(day, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: target).day
    }
}

/// The words the dog screens use.
public enum DogCopy {
    /// "Biscuit", "Biscuit & Pepper", "Biscuit, Pepper & Moose"
    public static func names(_ names: [String]) -> String? {
        let clean = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch clean.count {
        case 0: return nil
        case 1: return clean[0]
        default: return clean.dropLast().joined(separator: ", ") + " & " + clean.last!
        }
    }

    /// "New pup", "7 mo", "1 yr", "3 yrs" (nil without a birthday or for one in the future).
    public static func age(birthday: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let birthday, let born = DogDay.date(birthday, calendar: calendar), born <= now else { return nil }
        let c = calendar.dateComponents([.year, .month], from: born, to: now)
        let years = c.year ?? 0, months = c.month ?? 0
        if years >= 1 { return years == 1 ? "1 yr" : "\(years) yrs" }
        if months >= 1 { return "\(months) mo" }
        return "New pup"
    }

    /// "Golden Retriever · 3 yrs"
    public static func subtitle(_ dog: DogProfile, now: Date = Date(), calendar: Calendar = .current) -> String {
        [dog.breed.isEmpty ? nil : dog.breed, age(birthday: dog.birthday, now: now, calendar: calendar)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "Be the first to pet", "Petted once", "Petted 23 times"
    public static func petted(_ count: Int) -> String {
        switch count {
        case ..<1: return "Be the first to pet"
        case 1: return "Petted once"
        default: return "Petted \(count) times"
        }
    }

    public static func comments(_ count: Int) -> String {
        count == 0 ? "Comment" : (count == 1 ? "1 comment" : "\(count) comments")
    }

    /// The Dog Park's empty states, per tab.
    public static func emptyFeed(_ tab: DogFeedTab) -> String {
        switch tab {
        case .today: return "Can I pet dat dog? Nobody's posted today yet. Be the first 🐾"
        case .top: return "No top dogs this week yet. Post yours and get those pets!"
        case .following: return "Nothing from people you follow yet. Follow dog people around FavCircles and their pups show up here."
        }
    }

    /// Captions for the Pet button's little burst.
    public static let petCheers = ["Good dog!", "Who's a good pup?", "Pets delivered 🐾", "10/10 would pet again", "Bork!", "Such a good boy (or girl)!"]

    public static func cheer(for postId: String) -> String {
        petCheers[abs(postId.hashValue) % petCheers.count]
    }
}

/// How a vaccine stands today.
public enum DogVaccineStatus: Equatable, Sendable {
    case noDueDate
    case ok(days: Int)
    case dueSoon(days: Int)
    case dueToday
    case overdue(days: Int)

    public static let soonDays = 30

    public static func of(_ vaccine: DogVaccine, now: Date = Date(), calendar: Calendar = .current) -> DogVaccineStatus {
        guard let due = vaccine.dueOn, let days = DogDay.daysUntil(due, from: now, calendar: calendar) else { return .noDueDate }
        if days < 0 { return .overdue(days: -days) }
        if days == 0 { return .dueToday }
        if days <= soonDays { return .dueSoon(days: days) }
        return .ok(days: days)
    }

    /// "Due in 12 days", "Overdue by 3 days", "Due today", "Up to date"
    public var text: String {
        switch self {
        case .noDueDate: return "No due date"
        case .ok: return "Up to date"
        case .dueSoon(let d): return d == 1 ? "Due tomorrow" : "Due in \(d) days"
        case .dueToday: return "Due today"
        case .overdue(let d): return d == 1 ? "Overdue by 1 day" : "Overdue by \(d) days"
        }
    }

    public var needsAttention: Bool {
        switch self {
        case .dueSoon, .dueToday, .overdue: return true
        case .ok, .noDueDate: return false
        }
    }
}

/// Local notifications for one dog: vaccines due (30 and 7 days before)
/// and birthday / gotcha day, each at 9 AM unless quiet hours say later.
public enum DogReminderPlan {
    public struct Reminder: Equatable, Sendable {
        public let id: String
        public let fireAt: Date
        public let title: String
        public let body: String
    }

    public static let prefix = "dogs-"
    public static let hour = 9
    /// iOS keeps 64 pending per app; leave room for everyone else
    public static let cap = 24

    public static func reminders(dogs: [DogProfile], state: DogsState, now: Date = Date(), calendar: Calendar = .current,
                                 quietHours: WidgetQuietHours? = nil) -> [Reminder] {
        guard state.remindersOn else { return [] }
        var out: [Reminder] = []
        for dog in dogs {
            for vaccine in state.records(for: dog.id).vaccines {
                guard let due = vaccine.dueOn, let dueDate = DogDay.date(due, calendar: calendar) else { continue }
                for lead in [30, 7] {
                    guard let day = calendar.date(byAdding: .day, value: -lead, to: dueDate),
                          let at = fire(on: day, calendar: calendar, quietHours: quietHours), at > now else { continue }
                    out.append(Reminder(id: "\(prefix)vax-\(dog.id)-\(vaccine.id)-\(lead)", fireAt: at,
                                        title: "💉 \(dog.name)'s \(vaccine.name) is due \(lead == 7 ? "in a week" : "in a month")",
                                        body: "Due \(DogDay.display(due, calendar: calendar) ?? due). Book the vet so daycare and boarding stay happy."))
                }
            }
            if let birthday = dog.birthday, let next = nextAnniversary(of: birthday, after: now, calendar: calendar),
               let at = fire(on: next.date, calendar: calendar, quietHours: quietHours), at > now {
                out.append(Reminder(id: "\(prefix)bday-\(dog.id)", fireAt: at,
                                    title: "🎂 \(dog.name) turns \(next.years) today!",
                                    body: "Extra treats are mandatory. Post a birthday pic to the Dog Park 🐾"))
            }
            if let gotcha = dog.gotchaDay, let next = nextAnniversary(of: gotcha, after: now, calendar: calendar),
               let at = fire(on: next.date, calendar: calendar, quietHours: quietHours), at > now {
                out.append(Reminder(id: "\(prefix)gotcha-\(dog.id)", fireAt: at,
                                    title: "🏡 Happy gotcha day, \(dog.name)!",
                                    body: next.years == 1 ? "One year home today. Best day ever." : "\(next.years) years home today. Best day ever."))
            }
        }
        return Array(out.sorted { $0.fireAt < $1.fireAt }.prefix(cap))
    }

    /// The next time `day`'s month/day comes round on or after today (a Feb 29
    /// birthday is celebrated Feb 28 in other years), and how many years it marks.
    public static func nextAnniversary(of day: String, after now: Date, calendar: Calendar = .current) -> (date: Date, years: Int)? {
        guard let c = DogDay.components(day), let year = c.year, let month = c.month, let dayOfMonth = c.day else { return nil }
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: now)
        for y in [thisYear, thisYear + 1] where y > year {
            var d = dayOfMonth
            if month == 2 && dayOfMonth == 29 && calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: y, month: 2))!)?.count != 29 { d = 28 }
            guard let date = calendar.date(from: DateComponents(year: y, month: month, day: d)) else { continue }
            if date >= today { return (date, y - year) }
        }
        return nil
    }

    /// 9 AM that day, or the end of quiet hours when 9 AM falls inside them.
    static func fire(on day: Date, calendar: Calendar, quietHours: WidgetQuietHours?) -> Date? {
        var minutes = hour * 60
        if let quietHours, quietHours.contains(minute: minutes) { minutes = quietHours.endMinutes }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: calendar.startOfDay(for: day))
    }
}

/// Links into the widget (the landing page opens the app on that card).
public enum DogShareLink {
    public static let base = "https://api.favcircles.com/app/widget/dogs"

    public static func post(_ id: String) -> URL? { url(query: "post", id) }
    public static func daily(_ id: String) -> URL? { url(query: "daily", id) }

    private static func url(query: String, _ id: String) -> URL? {
        guard !id.isEmpty, let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "\(base)?\(query)=\(escaped)")
    }
}

/// The line under a document's title: "PDF · Added Oct 23, 2026", "3 pages · …".
public enum DogDocumentCopy {
    public static func detail(_ doc: DogDocument, calendar: Calendar = .current) -> String {
        let what: String
        switch doc.kind {
        case .pdf: what = "PDF"
        case .photos: what = doc.files.count == 1 ? "Photo" : "\(doc.files.count) pages"
        }
        // Certificates carried over from 0.53.0 have no added date
        guard doc.addedAt.timeIntervalSince1970 > 0 else { return what }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return "\(what) · Added \(formatter.string(from: doc.addedAt))"
    }
}

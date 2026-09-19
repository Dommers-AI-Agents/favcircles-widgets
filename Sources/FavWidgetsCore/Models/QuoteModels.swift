import Foundation

/// A topic someone can ask for their daily quote from.
public struct QuoteCategory: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var blurb: String

    private enum CodingKeys: String, CodingKey { case id, label, blurb }

    public init(id: String, label: String, blurb: String) {
        self.id = id
        self.label = label
        self.blurb = blurb
    }
}

/// What actually went out today, if it has.
public struct DailyQuote: Decodable, Equatable, Sendable {
    public var text: String
    public var author: String?
    public var category: String?
    public var sentAt: Date?

    public init(text: String, author: String? = nil, category: String? = nil, sentAt: Date? = nil) {
        self.text = text
        self.author = author
        self.category = category
        self.sentAt = sentAt
    }

    /// "— Marcus Aurelius", or nothing for the anonymous ones.
    public var attribution: String? {
        guard let author, !author.isEmpty else { return nil }
        return "— \(author)"
    }
}

/// The three things someone controls: whether, when, and about what — plus
/// whether it also lands in their inbox.
public struct QuoteSettings: Decodable, Equatable, Sendable {
    public var enabled: Bool
    public var categories: [String]
    /// "HH:mm" in their own timezone.
    public var time: String
    public var email: Bool

    public init(enabled: Bool = false, categories: [String] = ["motivation"], time: String = "08:00", email: Bool = false) {
        self.enabled = enabled
        self.categories = categories
        self.time = time
        self.email = email
    }

    private enum CodingKeys: String, CodingKey { case enabled, categories, time, email }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? ["motivation"]
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? "08:00"
        email = try c.decodeIfPresent(Bool.self, forKey: .email) ?? false
    }

    /// The hour as a date on an arbitrary day, for a wheel picker.
    public var timeAsDate: Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.first ?? 8
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    public static func time(from date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
    }
}

/// Everything the widget needs in one read.
public struct QuoteSettingsResponse: Decodable, Equatable, Sendable {
    public var prefs: QuoteSettings
    public var categories: [QuoteCategory]
    public var today: DailyQuote?

    public init(prefs: QuoteSettings = QuoteSettings(), categories: [QuoteCategory] = [], today: DailyQuote? = nil) {
        self.prefs = prefs
        self.categories = categories
        self.today = today
    }

    private enum CodingKeys: String, CodingKey { case prefs, categories, today }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prefs = try c.decodeIfPresent(QuoteSettings.self, forKey: .prefs) ?? QuoteSettings()
        categories = try c.decodeIfPresent([QuoteCategory].self, forKey: .categories) ?? []
        today = try c.decodeIfPresent(DailyQuote.self, forKey: .today)
    }
}

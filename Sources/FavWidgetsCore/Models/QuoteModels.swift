import Foundation

/// A topic someone can ask for their quotes from.
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

/// The latest line that went out today, if one has.
public struct DailyQuote: Decodable, Equatable, Sendable {
    /// The catalog id, so the card can open the reel on the very quote that
    /// went out. Optional: sends recorded before the reel existed have none.
    public var id: String?
    public var text: String
    public var author: String?
    public var category: String?
    public var sentAt: Date?
    /// Which of the day's times it was for ("HH:mm").
    public var slot: String?

    public init(id: String? = nil, text: String, author: String? = nil, category: String? = nil, sentAt: Date? = nil, slot: String? = nil) {
        self.id = id
        self.text = text
        self.author = author
        self.category = category
        self.sentAt = sentAt
        self.slot = slot
    }

    /// "— Marcus Aurelius", or nothing for the anonymous ones.
    public var attribution: String? {
        guard let author, !author.isEmpty else { return nil }
        return "— \(author)"
    }
}

/// The three things someone controls: whether, when (one time a day or
/// several), and about what — plus whether it also lands in their inbox.
public struct QuoteSettings: Decodable, Equatable, Sendable {
    public static let maxTimes = 6

    public var enabled: Bool
    public var categories: [String]
    /// "HH:mm" entries in their own timezone, sorted. Always at least one.
    public var times: [String]
    public var email: Bool

    /// The first slot; what older servers and clients call "the" time.
    public var time: String { times.first ?? "08:00" }

    public init(enabled: Bool = false, categories: [String] = ["motivation"], times: [String] = ["08:00"], email: Bool = false) {
        self.enabled = enabled
        self.categories = categories
        self.times = times.isEmpty ? ["08:00"] : times
        self.email = email
    }

    private enum CodingKeys: String, CodingKey { case enabled, categories, time, times, email }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? ["motivation"]
        let list = try c.decodeIfPresent([String].self, forKey: .times) ?? []
        let single = try c.decodeIfPresent(String.self, forKey: .time)
        times = list.isEmpty ? [single ?? "08:00"] : list
        email = try c.decodeIfPresent(Bool.self, forKey: .email) ?? false
    }

    /// "HH:mm" as a date on an arbitrary day, for a wheel picker.
    public static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.first ?? 8
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    public var timeAsDate: Date { Self.date(from: time) }

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

/// One card in the quote reel.
public struct QuoteReelItem: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var author: String?
    public var categories: [String]
    /// Background on the quote or the person who said it. Most rows have
    /// none, and the reel simply leaves the space empty then.
    public var context: String?

    public init(id: String, text: String, author: String? = nil, categories: [String] = [], context: String? = nil) {
        self.id = id
        self.text = text
        self.author = author
        self.categories = categories
        self.context = context
    }

    private enum CodingKeys: String, CodingKey { case id, text, author, categories, context }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        context = try c.decodeIfPresent(String.self, forKey: .context)
    }

    public var attribution: String? {
        guard let author, !author.isEmpty else { return nil }
        return "— \(author)"
    }
}

public struct QuoteFeedResponse: Decodable, Equatable, Sendable {
    public var start: String?
    public var categories: [QuoteCategory]
    public var quotes: [QuoteReelItem]

    private enum CodingKeys: String, CodingKey { case start, categories, quotes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(String.self, forKey: .start)
        categories = try c.decodeIfPresent([QuoteCategory].self, forKey: .categories) ?? []
        quotes = try c.decodeIfPresent([QuoteReelItem].self, forKey: .quotes) ?? []
    }
}

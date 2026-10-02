import Foundation

/// A postcard someone received, opened in the app from the printed card's QR
/// or the web page's "Open it in the app" (GET widgets/postcard/share/<token>).
public struct ReceivedPostcard: Decodable, Equatable, Sendable {
    public let token: String
    public let senderId: String?
    public let senderName: String
    public let imageUrl: String
    public let message: String
    public let placeName: String?
    public let placeCity: String?
    public let createdAt: String?
    /// The viewer sent it (scanning their own card).
    public let isMine: Bool
    /// "Send one back" can address it to them.
    public let senderIsConnection: Bool

    public init(token: String, senderId: String?, senderName: String, imageUrl: String, message: String,
                placeName: String?, placeCity: String?, createdAt: String?, isMine: Bool, senderIsConnection: Bool) {
        self.token = token
        self.senderId = senderId
        self.senderName = senderName
        self.imageUrl = imageUrl
        self.message = message
        self.placeName = placeName
        self.placeCity = placeCity
        self.createdAt = createdAt
        self.isMine = isMine
        self.senderIsConnection = senderIsConnection
    }
}

/// The words on the received-postcard sheet. Pure, so they're tested on a Mac.
public enum ReceivedPostcardCopy {
    public static func title(_ card: ReceivedPostcard) -> String {
        card.isMine ? "Your postcard" : "A postcard from \(card.senderName)"
    }

    /// "— Wesley · September 18, 2026"
    public static func byline(_ card: ReceivedPostcard, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var parts = ["— \(card.isMine ? "You" : card.senderName)"]
        if let date = card.createdAt.flatMap(parseDate) {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = timeZone
            f.dateStyle = .long
            f.timeStyle = .none
            parts.append(f.string(from: date))
        }
        return parts.joined(separator: " · ")
    }

    /// "From Midnight Diner, Charlotte", or nil.
    public static func place(_ card: ReceivedPostcard) -> String? {
        guard let name = card.placeName, !name.isEmpty else { return nil }
        if let city = card.placeCity, !city.isEmpty { return "From \(name), \(city)" }
        return "From \(name)"
    }

    public static func primaryButton(_ card: ReceivedPostcard) -> String {
        card.isMine ? "Send another" : "Send one back"
    }

    /// Under the button: who it will go to, or how it can be sent.
    public static func sendHint(_ card: ReceivedPostcard) -> String {
        if card.isMine { return "Snap a photo and make your next one." }
        if card.senderIsConnection { return "It'll be addressed to \(card.senderName)." }
        return "Make one and share it, email it, or mail a printed card."
    }

    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

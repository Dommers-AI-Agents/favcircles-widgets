import Foundation

/// How a sent postcard went out (Wes, 2026-10-18: "under Sent you can't
/// easily tell digitally sent from physically sent").
public enum PostcardSentKind: String, CaseIterable, Sendable {
    /// Printed and mailed through the post.
    case mailed
    /// Sent in a FavCircles chat.
    case app
    /// Emailed as a link to the card's web page.
    case email

    public var label: String {
        switch self {
        case .mailed: return "Mailed"
        case .app: return "In the app"
        case .email: return "Email"
        }
    }

    public var systemImage: String {
        switch self {
        case .mailed: return "envelope.fill"
        case .app: return "bubble.left.fill"
        case .email: return "at"
        }
    }
}

/// The Sent list's filter.
public enum PostcardSentFilter: String, CaseIterable, Sendable {
    case all, mailed, digital

    public var label: String {
        switch self {
        case .all: return "All"
        case .mailed: return "Mailed"
        case .digital: return "Digital"
        }
    }

    public func includes(_ record: PostcardRecord) -> Bool {
        switch self {
        case .all: return true
        case .mailed: return record.sentKind == .mailed
        case .digital: return record.sentKind != .mailed
        }
    }
}

public extension PostcardRecord {
    var sentKind: PostcardSentKind {
        if mailOrder != nil || messageId.hasPrefix("mail:") { return .mailed }
        if recipientId == "email" || messageId.hasPrefix("email:") { return .email }
        return .app
    }

    /// The card's picture. An emailed record's `imageURL` is the card's web
    /// page, not an image; a mailed record keeps its picture on the order.
    var cardImageURL: URL? {
        switch sentKind {
        case .email: return nil
        case .mailed: return imageURL ?? mailOrder?.imageUrl.flatMap(URL.init(string:))
        case .app: return imageURL
        }
    }

    /// An emailed card's web page, to open from its detail.
    var cardPageURL: URL? { sentKind == .email ? imageURL : nil }
}

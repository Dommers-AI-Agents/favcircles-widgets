import Foundation

/// A US postal address for a printed postcard. US-only at launch; adding
/// other countries means a country picker, a different price, and Lob's
/// international verification.
public struct PostcardMailAddress: Codable, Equatable, Sendable {
    public var name: String
    public var line1: String
    public var line2: String
    public var city: String
    public var state: String
    public var zip: String

    public init(name: String = "", line1: String = "", line2: String = "", city: String = "", state: String = "", zip: String = "") {
        self.name = name
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.state = state
        self.zip = zip
    }

    /// Trimmed, upper-cased state, and nothing else changed. The postal
    /// service's own corrections come back from the address check.
    public var normalized: PostcardMailAddress {
        PostcardMailAddress(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            line1: line1.trimmingCharacters(in: .whitespacesAndNewlines),
            line2: line2.trimmingCharacters(in: .whitespacesAndNewlines),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            state: state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            zip: zip.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Enough to be worth checking with the server. Deliberately loose — the
    /// real verdict is the address check, and rejecting odd-but-valid
    /// addresses on the device would block real mail.
    public var isComplete: Bool {
        let a = normalized
        return !a.name.isEmpty && !a.line1.isEmpty && !a.city.isEmpty
            && PostcardMailAddress.states.contains(a.state)
            && a.zip.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil
    }

    /// "123 Main St, Austin TX 78701"
    public var oneLine: String {
        let a = normalized
        let street = a.line2.isEmpty ? a.line1 : "\(a.line1), \(a.line2)"
        return "\(street), \(a.city) \(a.state) \(a.zip)"
    }

    public static let states: [String] = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY",
        "LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH",
        "OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","PR","VI","GU","AS","MP"
    ]
}

/// Where a printed postcard has got to. Mirrors the server's statuses, with
/// an `unknown` case so a new server status can never break an old build.
public enum PostcardMailStatus: String, Codable, Sendable {
    case created, authorized, submitting, submitted
    case inTransit = "in_transit"
    case delivered
    case canceled, rejected, expired, refunded
    case returnedToSender = "returned_to_sender"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PostcardMailStatus(rawValue: raw) ?? .unknown
    }

    /// Only while the card can still be pulled back before printing.
    public var isCancelable: Bool { self == .authorized }

    /// True while the person's money is still promised but not taken.
    public var isHeldNotCharged: Bool { self == .authorized || self == .submitting }

    public var isFinished: Bool {
        switch self {
        case .delivered, .canceled, .rejected, .expired, .refunded, .returnedToSender: return true
        default: return false
        }
    }
}

/// The mail leg of a postcard, stored alongside the sent record so history
/// can show it without a network call.
public struct PostcardMailOrder: Codable, Equatable, Sendable {
    public var orderId: String
    public var status: PostcardMailStatus
    public var priceCents: Int
    public var recipientName: String
    public var expectedDeliveryDate: String?
    public var cancelableUntil: Date?

    public init(orderId: String, status: PostcardMailStatus, priceCents: Int, recipientName: String,
                expectedDeliveryDate: String? = nil, cancelableUntil: Date? = nil) {
        self.orderId = orderId
        self.status = status
        self.priceCents = priceCents
        self.recipientName = recipientName
        self.expectedDeliveryDate = expectedDeliveryDate
        self.cancelableUntil = cancelableUntil
    }

    /// The line the sent panel and history row show. Leads with the money
    /// position while it still matters, because "am I charged?" is the
    /// question someone actually has in the first hour.
    public var displayStatus: String {
        switch status {
        case .created:
            return "Waiting for payment"
        case .authorized, .submitting:
            return "Mailing \(recipientName) · not charged until it prints"
        case .submitted, .inTransit:
            if let date = PostcardMailOrder.friendlyDate(expectedDeliveryDate) {
                return "Printed and mailed · arrives around \(date)"
            }
            return "Printed and mailed to \(recipientName)"
        case .delivered:
            return "Delivered to \(recipientName)"
        case .canceled:
            return "Canceled · you weren't charged"
        case .rejected:
            return "Couldn't be printed · you weren't charged"
        case .expired:
            return "Expired · you weren't charged"
        case .refunded:
            return "Refunded"
        case .returnedToSender:
            return "Returned to sender"
        case .unknown:
            return "Mailing \(recipientName)"
        }
    }

    public var priceText: String { PostcardMailOrder.price(cents: priceCents) }

    public static func price(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100).\(String(format: "%02d", cents % 100))"
    }

    /// "2026-09-20" -> "Sep 20". Returns nil rather than echoing an
    /// unparseable string back at the reader.
    public static func friendlyDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.timeZone = TimeZone(identifier: "UTC")
        return out.string(from: date)
    }
}

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

    /// The fields a person fills in, in the order they read them. `line2` is
    /// optional and never has a problem.
    public enum Field: CaseIterable, Sendable {
        case name, line1, city, state, zip
    }

    public func value(for field: Field) -> String {
        let a = normalized
        switch field {
        case .name: return a.name
        case .line1: return a.line1
        case .city: return a.city
        case .state: return a.state
        case .zip: return a.zip
        }
    }

    /// What's wrong with one field, phrased for the person looking at it —
    /// or nil if that field is fine. Shown right under the field, because a
    /// message at the bottom of the form sits behind the keyboard while the
    /// person is typing into the field it's about.
    public func problem(for field: Field) -> String? {
        let value = value(for: field)
        switch field {
        case .name: return value.isEmpty ? "Add the recipient's name." : nil
        case .line1: return value.isEmpty ? "Add the street address." : nil
        case .city: return value.isEmpty ? "Add the city." : nil
        case .state: return PostcardMailAddress.states.contains(value) ? nil : "Choose the state."
        case .zip:
            if value.isEmpty { return "Add the ZIP code." }
            if value.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) == nil {
                return "ZIP codes are 5 digits, like 95014."
            }
            return nil
        }
    }

    /// The first thing stopping this address from being mailable, in the
    /// order the person reads the form.
    ///
    /// This exists because "Fill in the mailing address" is a lie once every
    /// field has something in it. App Review typed a ten-digit number into ZIP,
    /// got a greyed-out Send and that sentence, and rejected the build as
    /// "the send button was not responsive" — reasonably, since the app was
    /// telling them to do something they had already done. Name the field.
    public var firstProblem: String? {
        for field in Field.allCases {
            if let problem = problem(for: field) { return problem }
        }
        return nil
    }

    /// Enough to be worth checking with the server. Deliberately loose — the
    /// real verdict is the address check, and rejecting odd-but-valid
    /// addresses on the device would block real mail.
    public var isComplete: Bool { firstProblem == nil }

    /// The five-digit part, so a "+4" the postal service added doesn't read as
    /// a change of ZIP.
    public var zip5: String { String(normalized.zip.prefix(5)) }

    /// Does the address the postal service returned describe a different
    /// place from the one the person typed?
    ///
    /// Address verification rewrites everything — "1516 Bay Plaza" comes back
    /// "1516 BAY PLZ", and that's fine, it's the same door. But it will also
    /// happily take a street, a city and a wrong ZIP, find the one real address
    /// that matches, and return it as deliverable. Someone who typed a Charlotte
    /// ZIP under a New Jersey street had made a mistake somewhere, and the card
    /// must not go out until they've seen the correction and said yes.
    ///
    /// Material: a different ZIP, state, city or house number. Not material:
    /// case, abbreviations, a ZIP+4 suffix, a name (never verified).
    public func differsMaterially(from typed: PostcardMailAddress) -> Bool {
        let mine = normalized
        let theirs = typed.normalized
        if mine.zip5 != theirs.zip5 { return true }
        if mine.state != theirs.state { return true }
        if mine.city.uppercased() != theirs.city.uppercased() { return true }
        if mine.houseNumber != theirs.houseNumber { return true }
        return false
    }

    private var houseNumber: String {
        normalized.line1.split(separator: " ").first.map { String($0).uppercased() } ?? ""
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
    /// What the server knows about the card itself, so an order this phone
    /// never recorded (the send looked like a failure, the app was reinstalled)
    /// can still be shown in history. Absent on records written before 0.18.
    public var imageUrl: String?
    public var message: String?
    public var createdAt: Date?

    public init(orderId: String, status: PostcardMailStatus, priceCents: Int, recipientName: String,
                expectedDeliveryDate: String? = nil, cancelableUntil: Date? = nil,
                imageUrl: String? = nil, message: String? = nil, createdAt: Date? = nil) {
        self.orderId = orderId
        self.status = status
        self.priceCents = priceCents
        self.recipientName = recipientName
        self.expectedDeliveryDate = expectedDeliveryDate
        self.cancelableUntil = cancelableUntil
        self.imageUrl = imageUrl
        self.message = message
        self.createdAt = createdAt
    }

    /// The history row's id for this order, shared by the send path and the
    /// reconciler so the two never write the same card twice.
    public var recordMessageId: String { "mail:\(orderId)" }

    /// The line the sent panel and history row show. Leads with the money
    /// position while it still matters, because "am I charged?" is the
    /// question someone actually has in the first hour.
    public var displayStatus: String {
        switch status {
        case .created:
            return "Waiting for payment"
        case .authorized, .submitting:
            return "Mailing \(recipientName) · not charged until it prints"
        // Lob's expected date is its outer bound (production + 5–7 business
        // days); the honest, readable line is the typical window (Wes,
        // 2026-09-18).
        case .submitted:
            return "Printed and mailed to \(recipientName) · typically arrives in 4 to 6 business days"
        case .inTransit:
            return "In the mail to \(recipientName) · typically arrives in 4 to 6 business days"
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

import Foundation
import CoreGraphics

// Fridge Mail: a parent queues kids' drawings and photos, names up to three
// grandparents, and the server mails one printed postcard per grandparent
// every week. All of this state is server-owned (the weekly run happens
// with the phone in a drawer), so these are wire types, not documents.

/// Where the plan stands in one read. Mirrors the server's `present()`.
public struct FridgeMailPlan: Decodable, Equatable, Sendable {
    public var familyName: String
    public var recipients: [FridgeMailRecipient]
    public var queue: [FridgeMailQueueItem]
    /// 0 = Sunday … 6 = Saturday, the JavaScript convention. Indexes
    /// `Calendar.weekdaySymbols` directly.
    public var weekday: Int
    public var timezone: String
    public var status: String
    public var cardsRemaining: Int
    public var subscription: FridgeMailSubscription?
    public var lastSentAt: Date?
    public var nextSendAt: Date?
    public var entitlement: FridgeMailEntitlement
    public var packs: [FridgeMailPack]
    public var subscriptionPriceCents: Int
    public var currency: String

    public init(familyName: String = "", recipients: [FridgeMailRecipient] = [], queue: [FridgeMailQueueItem] = [],
                weekday: Int = 1, timezone: String = "America/New_York", status: String = "active", cardsRemaining: Int = 0,
                subscription: FridgeMailSubscription? = nil, lastSentAt: Date? = nil, nextSendAt: Date? = nil,
                entitlement: FridgeMailEntitlement = FridgeMailEntitlement(), packs: [FridgeMailPack] = [],
                subscriptionPriceCents: Int = 799, currency: String = "usd") {
        self.familyName = familyName
        self.recipients = recipients
        self.queue = queue
        self.weekday = weekday
        self.timezone = timezone
        self.status = status
        self.cardsRemaining = cardsRemaining
        self.subscription = subscription
        self.lastSentAt = lastSentAt
        self.nextSendAt = nextSendAt
        self.entitlement = entitlement
        self.packs = packs
        self.subscriptionPriceCents = subscriptionPriceCents
        self.currency = currency
    }

    public var isPaused: Bool { status == "paused" }
    public var isSubscribed: Bool { subscription?.isActive ?? false }
    /// Drawings still waiting to be mailed, in mailing order.
    public var pending: [FridgeMailQueueItem] { queue.filter { $0.sentAt == nil } }
    public var nextItem: FridgeMailQueueItem? { pending.first }
    /// Nothing set up yet: the full view opens on the explainer.
    public var isEmpty: Bool { recipients.isEmpty && queue.isEmpty && !isSubscribed && cardsRemaining == 0 }
    /// This week's run would mail to everyone.
    public var isFullyCovered: Bool { !recipients.isEmpty && entitlement.covered >= recipients.count }
}

public struct FridgeMailRecipient: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var relation: String
    public var address: PostcardMailAddress

    public init(id: String, name: String, relation: String = "", address: PostcardMailAddress) {
        self.id = id
        self.name = name
        self.relation = relation
        self.address = address
    }

    private enum CodingKeys: String, CodingKey { case id, name, relation, address }
    private enum AddressKeys: String, CodingKey { case line1, line2, city, state, zip }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? ""
        // The server stores the USPS-standardized address without a name;
        // the recipient's name is the name.
        let a = try c.nestedContainer(keyedBy: AddressKeys.self, forKey: .address)
        address = PostcardMailAddress(
            name: name,
            line1: try a.decodeIfPresent(String.self, forKey: .line1) ?? "",
            line2: try a.decodeIfPresent(String.self, forKey: .line2) ?? "",
            city: try a.decodeIfPresent(String.self, forKey: .city) ?? "",
            state: try a.decodeIfPresent(String.self, forKey: .state) ?? "",
            zip: try a.decodeIfPresent(String.self, forKey: .zip) ?? ""
        )
    }

    /// "Grandma Sue" or, with no relation, just the name.
    public var displayName: String {
        let r = relation.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? name : "\(r) \(name)"
    }
}

public struct FridgeMailQueueItem: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var imageUrl: String
    public var childName: String
    public var ageText: String
    public var note: String
    public var addedAt: Date
    public var sentAt: Date?

    public init(id: String, imageUrl: String, childName: String, ageText: String = "", note: String = "", addedAt: Date, sentAt: Date? = nil) {
        self.id = id
        self.imageUrl = imageUrl
        self.childName = childName
        self.ageText = ageText
        self.note = note
        self.addedAt = addedAt
        self.sentAt = sentAt
    }

    public var imageURL: URL? { URL(string: imageUrl) }
}

public struct FridgeMailSubscription: Decodable, Equatable, Sendable {
    public var status: String
    public var quantity: Int
    public var currentPeriodEnd: Date?
    public var cancelAtPeriodEnd: Bool

    public init(status: String, quantity: Int, currentPeriodEnd: Date? = nil, cancelAtPeriodEnd: Bool = false) {
        self.status = status
        self.quantity = quantity
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    public var isActive: Bool { status == "active" || status == "trialing" }
    public var isPastDue: Bool { status == "past_due" }
}

public struct FridgeMailEntitlement: Decodable, Equatable, Sendable {
    /// Recipients this week's run can pay for (subscription slots + credits).
    public var covered: Int
    public var recipients: Int
    public var subscribedSlots: Int
    /// nil when the subscription alone covers everyone.
    public var weeksOfCredits: Int?

    public init(covered: Int = 0, recipients: Int = 0, subscribedSlots: Int = 0, weeksOfCredits: Int? = nil) {
        self.covered = covered
        self.recipients = recipients
        self.subscribedSlots = subscribedSlots
        self.weeksOfCredits = weeksOfCredits
    }
}

public struct FridgeMailPack: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var cards: Int
    public var amountCents: Int
    public var label: String

    public init(id: String, cards: Int, amountCents: Int, label: String) {
        self.id = id
        self.cards = cards
        self.amountCents = amountCents
        self.label = label
    }

    public var priceText: String { PostcardMailOrder.price(cents: amountCents) }
    /// "$2.60 a card"
    public var perCardText: String { PostcardMailOrder.price(cents: Int((Double(amountCents) / Double(max(1, cards))).rounded())) + " a card" }
}

/// One mailed card, from the server's history.
public struct FridgeMailCard: Decodable, Equatable, Identifiable, Sendable {
    public var cardId: String
    public var status: PostcardMailStatus
    public var recipientId: String?
    public var recipientName: String?
    public var childName: String
    public var note: String
    public var imageUrl: String?
    public var expectedDeliveryDate: String?
    public var createdAt: Date

    public var id: String { cardId }
    public var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }

    public init(cardId: String, status: PostcardMailStatus, recipientId: String? = nil, recipientName: String? = nil,
                childName: String = "", note: String = "", imageUrl: String? = nil, expectedDeliveryDate: String? = nil, createdAt: Date) {
        self.cardId = cardId
        self.status = status
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.childName = childName
        self.note = note
        self.imageUrl = imageUrl
        self.expectedDeliveryDate = expectedDeliveryDate
        self.createdAt = createdAt
    }
}

/// Kept for callers written before `WidgetJSON` existed.
public typealias FridgeMailJSON = WidgetJSON

/// The words. Kept in Core so the copy is testable without a simulator.
public enum FridgeMailCopy {
    public static let subscriptionPriceText = "$7.99"
    public static let noteMaxChars = 200

    public static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        guard symbols.indices.contains(weekday) else { return "Monday" }
        return symbols[weekday]
    }

    /// The card's one-line summary. Leads with whatever the person has to
    /// do next; only once everything is in place does it talk about the
    /// next mailing.
    public static func cardSummary(_ plan: FridgeMailPlan?, calendar: Calendar = .current) -> String {
        guard let plan, !plan.isEmpty else { return "Kids' drawings, mailed to Grandma every week" }
        if plan.recipients.isEmpty { return "Add a grandparent to start mailing" }
        if plan.pending.isEmpty { return "Add a drawing · nothing queued for \(weekdayName(plan.weekday, calendar: calendar))" }
        if plan.entitlement.covered == 0 { return "Out of cards · \(plan.pending.count) queued" }
        if plan.isPaused { return "Paused · \(plan.pending.count) queued" }
        var parts = ["Next card \(weekdayName(plan.weekday, calendar: calendar))", "\(plan.pending.count) queued"]
        parts.append(creditsLine(plan))
        return parts.joined(separator: " · ")
    }

    /// "subscribed", "5 cards left", "no cards left".
    public static func creditsLine(_ plan: FridgeMailPlan) -> String {
        if plan.isSubscribed && plan.isFullyCovered { return "subscribed" }
        if plan.cardsRemaining == 0 { return plan.isSubscribed ? "subscribed" : "no cards left" }
        return plan.cardsRemaining == 1 ? "1 card left" : "\(plan.cardsRemaining) cards left"
    }

    /// The Plan section's status line.
    public static func planStatus(_ plan: FridgeMailPlan, calendar: Calendar = .current) -> String {
        var lines: [String] = []
        if let sub = plan.subscription, sub.isActive {
            let slots = sub.quantity == 1 ? "1 grandparent" : "\(sub.quantity) grandparents"
            if sub.cancelAtPeriodEnd, let end = sub.currentPeriodEnd {
                lines.append("Subscription ends \(shortDate(end, calendar: calendar)) · \(slots)")
            } else if let end = sub.currentPeriodEnd {
                lines.append("Subscribed · \(slots) · renews \(shortDate(end, calendar: calendar))")
            } else {
                lines.append("Subscribed · \(slots)")
            }
        } else if let sub = plan.subscription, sub.isPastDue {
            lines.append("Subscription payment failed · update your card in Wallet")
        }
        if plan.cardsRemaining > 0 {
            var credit = plan.cardsRemaining == 1 ? "1 prepaid card" : "\(plan.cardsRemaining) prepaid cards"
            if let weeks = plan.entitlement.weeksOfCredits, !plan.recipients.isEmpty {
                credit += weeks == 1 ? " · about 1 week" : " · about \(weeks) weeks"
            }
            lines.append(credit)
        }
        if lines.isEmpty { lines.append("No cards yet") }
        return lines.joined(separator: "\n")
    }

    /// What this week's run will do, for the Next card section.
    public static func nextSendLine(_ plan: FridgeMailPlan, calendar: Calendar = .current) -> String {
        if plan.isPaused { return "Paused — nothing goes out until you resume" }
        if plan.recipients.isEmpty { return "Add a grandparent and we'll mail it \(weekdayName(plan.weekday, calendar: calendar))" }
        if plan.pending.isEmpty { return "Add a drawing and we'll mail it \(weekdayName(plan.weekday, calendar: calendar))" }
        let who = plan.recipients.count == 1 ? plan.recipients[0].displayName : "\(plan.recipients.count) grandparents"
        if plan.entitlement.covered == 0 { return "Needs cards — buy a pack or subscribe to mail it to \(who)" }
        if plan.entitlement.covered < plan.recipients.count {
            return "Goes to \(plan.entitlement.covered) of \(plan.recipients.count) grandparents \(weekdayName(plan.weekday, calendar: calendar)) — add cards to cover everyone"
        }
        if let next = plan.nextSendAt {
            return "Goes to \(who) \(relativeDay(next, calendar: calendar))"
        }
        return "Goes to \(who) \(weekdayName(plan.weekday, calendar: calendar))"
    }

    /// The Sent row's status. Prepaid cards never mention charges.
    public static func cardStatus(_ status: PostcardMailStatus, recipientName: String?) -> String {
        let who = (recipientName ?? "").isEmpty ? "Grandma" : recipientName!
        switch status {
        case .created, .authorized, .submitting: return "Printing for \(who)"
        case .submitted: return "Printed and mailed to \(who) · typically arrives in 4 to 6 business days"
        case .inTransit: return "In the mail to \(who) · typically arrives in 4 to 6 business days"
        case .delivered: return "Delivered to \(who)"
        case .canceled: return "Canceled"
        case .rejected, .expired: return "Couldn't be printed · card credited back"
        case .refunded: return "Credited back"
        case .returnedToSender: return "Returned to sender"
        case .unknown: return "Sent to \(who)"
        }
    }

    /// The text printed on the back: "Maya, age 4 · September 18, 2026".
    public static func backHeadline(childName: String, ageText: String, date: Date, calendar: Calendar = .current) -> String {
        var who = childName.trimmingCharacters(in: .whitespaces)
        if who.isEmpty { who = "Made with love" }
        let age = ageText.trimmingCharacters(in: .whitespaces)
        if !age.isEmpty { who += ", age \(age)" }
        let f = DateFormatter()
        f.calendar = calendar
        f.dateStyle = .long
        f.timeStyle = .none
        return "\(who) · \(f.string(from: date))"
    }

    public static func signature(familyName: String) -> String {
        let name = familyName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "— With love" : "— From \(name)"
    }

    static func shortDate(_ date: Date, calendar: Calendar) -> String {
        WidgetDateCopy.formatted(date, template: "MMM d", calendar: calendar)
    }

    static func relativeDay(_ date: Date, calendar: Calendar) -> String {
        WidgetDateCopy.futureDay(date, calendar: calendar)
    }
}

/// Geometry for the printed front: any drawing (portrait, square, a phone
/// photo) sits whole inside a warm frame with a name strip below, never
/// cropped. A child's drawing cut at the edge is the one complaint we can't
/// answer.
public enum FridgeMailLayout {
    /// The largest rect with `image`'s aspect that fits inside `canvas`
    /// after `inset` on every side and `stripHeight` reserved at the bottom,
    /// centered horizontally, and centered in the remaining vertical space.
    public static func fit(image: CGSize, canvas: CGSize, inset: CGFloat, stripHeight: CGFloat) -> CGRect {
        let availableWidth = max(1, canvas.width - inset * 2)
        let availableHeight = max(1, canvas.height - inset * 2 - stripHeight)
        guard image.width > 0, image.height > 0 else {
            return CGRect(x: inset, y: inset, width: availableWidth, height: availableHeight)
        }
        let scale = min(availableWidth / image.width, availableHeight / image.height)
        let width = image.width * scale
        let height = image.height * scale
        let x = inset + (availableWidth - width) / 2
        let y = inset + (availableHeight - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

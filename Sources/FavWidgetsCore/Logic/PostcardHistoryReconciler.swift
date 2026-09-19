import Foundation

/// Fills the gaps between the server's printed-postcard orders and the
/// history this phone wrote at send time.
///
/// The phone records a card when its own send succeeds. That misses a card
/// whenever the send *looked* like a failure but wasn't (a wallet sheet that
/// timed out after the charge went through), and everything sent from
/// another phone or before a reinstall. The server's order list is the
/// truth for printed cards, so history is topped up from it.
public enum PostcardHistoryReconciler {
    public struct Missing: Equatable, Sendable {
        public let month: MonthKey
        public let record: PostcardRecord
    }

    /// Orders that were never authorized are not sends — a dismissed wallet
    /// leaves a `created` row behind that nobody should see as "sent".
    public static func countsAsSent(_ status: PostcardMailStatus) -> Bool {
        switch status {
        case .created, .expired, .unknown: return false
        default: return true
        }
    }

    /// - Parameters:
    ///   - orders: the server's orders, any status.
    ///   - knownMessageIds: the `messageId`s of every record already in the
    ///     months the caller has loaded. Check the current AND previous month
    ///     before calling: a card sent near midnight can sit in a different
    ///     month locally than its server `createdAt` says.
    ///   - templateId: history rows need one; the server doesn't know which
    ///     template printed, so the person's last-used one stands in.
    public static func missingRecords(orders: [PostcardMailOrder], knownMessageIds: Set<String>,
                                      templateId: String, calendar: Calendar = .current, now: Date = Date()) -> [Missing] {
        orders.compactMap { order in
            guard countsAsSent(order.status), !knownMessageIds.contains(order.recordMessageId) else { return nil }
            let sentAt = order.createdAt ?? now
            let record = PostcardRecord(
                messageId: order.recordMessageId, conversationId: "",
                recipientId: "mail", recipientName: order.recipientName,
                templateId: templateId, message: order.message ?? "",
                imageURL: order.imageUrl.flatMap(URL.init(string:)),
                place: nil, sentAt: sentAt, mailOrder: order
            )
            return Missing(month: MonthKey(sentAt, calendar: calendar), record: record)
        }
    }
}

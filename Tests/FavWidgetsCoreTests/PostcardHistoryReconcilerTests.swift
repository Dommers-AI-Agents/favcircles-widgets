import Testing
import Foundation
@testable import FavWidgetsCore

/// The server's order list tops up the phone's sent history.
struct PostcardHistoryReconcilerTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    private func order(_ id: String, _ status: PostcardMailStatus, createdAt: String? = "2026-09-19T18:19:59Z",
                       message: String? = "Hi", image: String? = "https://storage.example/x.jpg") -> PostcardMailOrder {
        PostcardMailOrder(orderId: id, status: status, priceCents: 299, recipientName: "Sgroi Family",
                          imageUrl: image, message: message,
                          createdAt: createdAt.flatMap { ISO8601DateFormatter().date(from: $0) })
    }

    @Test func aSubmittedOrderThePhoneNeverRecordedBecomesAHistoryRow() {
        let missing = PostcardHistoryReconciler.missingRecords(orders: [order("A", .submitted)], knownMessageIds: [], templateId: "classic", calendar: utc)
        #expect(missing.count == 1)
        let m = missing[0]
        #expect(m.month == MonthKey(year: 2026, month: 9))
        #expect(m.record.messageId == "mail:A")
        #expect(m.record.recipientId == "mail")
        #expect(m.record.recipientName == "Sgroi Family")
        #expect(m.record.message == "Hi")
        #expect(m.record.imageURL?.absoluteString == "https://storage.example/x.jpg")
        #expect(m.record.templateId == "classic")
        #expect(m.record.mailOrder?.orderId == "A")
    }

    @Test func recordsAlreadyWrittenBySendAreNotDuplicated() {
        let missing = PostcardHistoryReconciler.missingRecords(orders: [order("A", .submitted), order("B", .delivered)],
                                                                knownMessageIds: ["mail:A"], templateId: "classic", calendar: utc)
        #expect(missing.map(\.record.messageId) == ["mail:B"])
    }

    @Test func ordersThatWereNeverAuthorizedAreNotSends() {
        let orders: [PostcardMailOrder] = [order("C", .created), order("E", .expired), order("U", .unknown),
                                           order("K", .canceled), order("R", .refunded), order("T", .inTransit)]
        let ids = PostcardHistoryReconciler.missingRecords(orders: orders, knownMessageIds: [], templateId: "t", calendar: utc).map(\.record.messageId)
        #expect(ids == ["mail:K", "mail:R", "mail:T"])
    }

    @Test func missingServerFieldsFallBackSafely() {
        let now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        let missing = PostcardHistoryReconciler.missingRecords(orders: [order("A", .submitted, createdAt: nil, message: nil, image: nil)],
                                                                knownMessageIds: [], templateId: "t", calendar: utc, now: now)
        #expect(missing[0].month == MonthKey(year: 2026, month: 10))
        #expect(missing[0].record.message == "")
        #expect(missing[0].record.imageURL == nil)
        #expect(missing[0].record.sentAt == now)
    }
}

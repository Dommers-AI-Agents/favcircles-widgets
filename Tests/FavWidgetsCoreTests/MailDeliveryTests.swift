import Foundation
import Testing
@testable import FavWidgetsCore

/// "Processed for delivery" is not "delivered" (Wes, 2026-10-02).
struct MailDeliveryTests {
    private let now = Date(timeIntervalSince1970: 1_790_900_000)

    @Test func outForDeliveryUntilAScanOrThreeDays() {
        let hourAgo = now.addingTimeInterval(-3600)
        #expect(MailDelivery.isOutForDelivery(status: .delivered, outForDeliveryAt: hourAgo, deliveryConfirmed: nil, now: now))
        #expect(!MailDelivery.isOutForDelivery(status: .delivered, outForDeliveryAt: hourAgo, deliveryConfirmed: true, now: now))
        #expect(!MailDelivery.isOutForDelivery(status: .delivered, outForDeliveryAt: now.addingTimeInterval(-4 * 86_400), deliveryConfirmed: nil, now: now))
        #expect(!MailDelivery.isOutForDelivery(status: .delivered, outForDeliveryAt: nil, deliveryConfirmed: nil, now: now)) // older records
        #expect(!MailDelivery.isOutForDelivery(status: .inTransit, outForDeliveryAt: hourAgo, deliveryConfirmed: nil, now: now))
    }

    @Test func postcardAndFridgeMailWording() throws {
        let order = PostcardMailOrder(orderId: "o", status: .delivered, priceCents: 199, recipientName: "Linda", outForDeliveryAt: Date())
        #expect(order.displayStatus == "Out for delivery to Linda · arrives today or tomorrow")
        let confirmed = PostcardMailOrder(orderId: "o", status: .delivered, priceCents: 199, recipientName: "Linda", outForDeliveryAt: Date(), deliveryConfirmed: true)
        #expect(confirmed.displayStatus == "Delivered to Linda")
        #expect(FridgeMailCopy.cardStatus(.delivered, recipientName: "Grandma Sal", outForDelivery: true) == "Out for delivery to Grandma Sal · arrives today or tomorrow")
        #expect(FridgeMailCopy.cardStatus(.delivered, recipientName: "Grandma Sal") == "Delivered to Grandma Sal")
        // An older stored record (no new keys) still decodes
        let old = try JSONDecoder().decode(PostcardMailOrder.self, from: Data(#"{"orderId":"o","status":"delivered","priceCents":199,"recipientName":"Linda"}"#.utf8))
        #expect(old.displayStatus == "Delivered to Linda")
    }
}

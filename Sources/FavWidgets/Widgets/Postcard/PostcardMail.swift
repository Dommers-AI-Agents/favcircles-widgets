import Foundation
import FavWidgetsCore

/// "Mail a printed postcard": talks to the widgets' own mail endpoints and
/// runs the pay-then-print flow.
///
/// The ordering here is the whole feature. Apple Pay places a *hold*, not a
/// charge. The card is printed an hour later and only then is the money
/// taken, so canceling inside that hour costs the customer nothing and costs
/// us nothing either — voiding a hold is free, while refunding a charge is
/// not.
enum PostcardMail {
    // MARK: Wire types

    struct Config: Decodable {
        let enabled: Bool
        let priceCents: Int
        let currency: String
        let cancelWindowMinutes: Int
        let messageMaxChars: Int
        let publishableKey: String?
        let applePayMerchantId: String?
        let policyText: String?

        /// Everything the server needs before it can take money. A missing
        /// key means the account isn't wired up yet, not that the user did
        /// something wrong.
        var isUsable: Bool {
            enabled && !(publishableKey ?? "").isEmpty && !(applePayMerchantId ?? "").isEmpty
        }
    }

    struct Quote: Decodable {
        let deliverable: Bool
        let standardized: Standardized
        let priceCents: Int

        struct Standardized: Decodable {
            let name: String?
            let line1: String
            let line2: String?
            let city: String
            let state: String
            let zip: String
        }

        var address: PostcardMailAddress {
            PostcardMailAddress(
                name: standardized.name ?? "",
                line1: standardized.line1,
                line2: standardized.line2 ?? "",
                city: standardized.city,
                state: standardized.state,
                zip: standardized.zip
            )
        }
    }

    struct Order: Decodable {
        let orderId: String
        let status: PostcardMailStatus
        let amountCents: Int
        let recipientName: String?
        let expectedDeliveryDate: String?
        let cancelableUntil: Date?
        let canCancel: Bool
        let imageUrl: String?
        let message: String?
        let createdAt: Date?
        let printerHold: Bool?

        var asRecordOrder: PostcardMailOrder {
            PostcardMailOrder(
                orderId: orderId,
                status: status,
                priceCents: amountCents,
                recipientName: recipientName ?? "",
                expectedDeliveryDate: expectedDeliveryDate,
                cancelableUntil: cancelableUntil,
                imageUrl: imageUrl,
                message: message,
                createdAt: createdAt,
                printerHold: printerHold
            )
        }
    }

    private struct CreateResponse: Decodable {
        let orderId: String
        let paymentIntentClientSecret: String
    }

    private struct OrderResponse: Decodable { let order: Order }
    private struct OrdersResponse: Decodable { let orders: [Order] }

    // MARK: Calls

    static func config(context: WidgetContext) async throws -> Config {
        try decode(Config.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/postcard/mail/config")))
    }

    static func quote(context: WidgetContext, address: PostcardMailAddress) async throws -> Quote {
        let a = address.normalized
        let body = try JSONSerialization.data(withJSONObject: ["recipient": [
            "name": a.name, "line1": a.line1, "line2": a.line2, "city": a.city, "state": a.state, "zip": a.zip
        ]])
        return try decode(Quote.self, from: await context.host.request(WidgetAPIRequest(.post, "widgets/postcard/mail/quote", body: body)))
    }

    static func orders(context: WidgetContext) async throws -> [Order] {
        try decode(OrdersResponse.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/postcard/mail/orders"))).orders
    }

    static func cancel(context: WidgetContext, orderId: String) async throws -> Order {
        try decode(OrderResponse.self, from: await context.host.request(
            WidgetAPIRequest(.post, "widgets/postcard/mail/orders/\(orderId)/cancel"))).order
    }

    // MARK: The flow

    /// Everything that has to happen before the Send tap, so the tap itself
    /// can open the wallet with no network in front of it. Apple refuses to
    /// present Apple Pay after asynchronous work.
    struct Prepared {
        let printImageURL: URL
        let address: PostcardMailAddress
        let config: Config
    }

    /// Renders and uploads print-resolution artwork. Run this while the
    /// person is still filling in the address.
    static func prepareArtwork(context: WidgetContext, jpeg: Data) async throws -> URL {
        try await context.host.uploadPrintImage(jpeg)
    }

    /// Presents Apple Pay, creates the order inside the sheet, and confirms
    /// the hold. Returns nil when the person simply dismissed the wallet —
    /// that is a choice, not a failure, and nothing was held.
    static func purchase(
        context: WidgetContext,
        prepared: Prepared,
        message: String,
        templateId: String,
        place: WidgetPlaceRef?
    ) async throws -> PostcardMailOrder? {
        guard let publishableKey = prepared.config.publishableKey,
              let merchantId = prepared.config.applePayMerchantId else {
            throw WidgetAPIError(status: 503, message: "Mailing printed postcards isn't available yet.")
        }

        let orderId = UUID().uuidString
        let address = prepared.address.normalized

        let request = WidgetPaymentRequest(
            publishableKey: publishableKey,
            merchantDisplayName: "FavCircles",
            applePayMerchantId: merchantId,
            amountCents: prepared.config.priceCents,
            currency: prepared.config.currency,
            summaryLabel: "Postcard to \(address.name)"
        ) {
            // Runs after the wallet authorizes, inside the payment sheet.
            var body: [String: Any] = [
                "orderId": orderId,
                "imageUrl": prepared.printImageURL.absoluteString,
                "message": message,
                "templateId": templateId,
                "recipient": [
                    "name": address.name, "line1": address.line1, "line2": address.line2,
                    "city": address.city, "state": address.state, "zip": address.zip
                ]
            ]
            if let place {
                var ref: [String: Any] = ["name": place.name]
                if let city = place.city { ref["city"] = city }
                body["placeRef"] = ref
            }
            let data = try await context.host.request(WidgetAPIRequest(
                .post, "widgets/postcard/mail/orders", body: try JSONSerialization.data(withJSONObject: body)))
            return try decode(CreateResponse.self, from: data).paymentIntentClientSecret
        }

        let result = try await context.host.collectPayment(request)
        guard case .completed = result else { return nil }

        // Tell the server the hold is real. If this call fails the money is
        // still held and the server's own webhook records it, so the card
        // still goes out — never imply otherwise to the user.
        do {
            let data = try await context.host.request(WidgetAPIRequest(.post, "widgets/postcard/mail/orders/\(orderId)/confirm"))
            return try decode(OrderResponse.self, from: data).order.asRecordOrder
        } catch {
            return PostcardMailOrder(
                orderId: orderId,
                status: .authorized,
                priceCents: prepared.config.priceCents,
                recipientName: address.name
            )
        }
    }

    // MARK: Decoding

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try WidgetJSON.decode(type, from: data)
    }
}

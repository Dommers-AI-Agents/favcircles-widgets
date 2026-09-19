import Foundation
import FavWidgetsCore

/// The Fridge Mail endpoints. Every mutating call returns the whole plan,
/// so the store never has to guess what changed.
enum FridgeMailAPI {
    private struct PlanResponse: Decodable { let plan: FridgeMailPlan }
    private struct CardsResponse: Decodable { let cards: [FridgeMailCard] }
    private struct PackOrderResponse: Decodable {
        let orderId: String
        let paymentIntentClientSecret: String
        let amountCents: Int
        let cards: Int
    }
    private struct SetupResponse: Decodable {
        let setupIntentId: String
        let setupIntentClientSecret: String
        let priceCents: Int
        let quantity: Int
    }

    // MARK: Plan

    static func plan(context: WidgetContext) async throws -> FridgeMailPlan {
        try await planCall(context, .get, "widgets/fridgemail/plan")
    }

    static func updatePlan(context: WidgetContext, weekday: Int? = nil, timezone: String? = nil,
                           familyName: String? = nil, status: String? = nil) async throws -> FridgeMailPlan {
        var body: [String: Any] = [:]
        if let weekday { body["weekday"] = weekday }
        if let timezone { body["timezone"] = timezone }
        if let familyName { body["familyName"] = familyName }
        if let status { body["status"] = status }
        return try await planCall(context, .put, "widgets/fridgemail/plan", body: body)
    }

    // MARK: Recipients

    /// The server verifies the address with USPS and stores the corrected
    /// form; a bad address comes back as a 422 with a readable message.
    static func addRecipient(context: WidgetContext, name: String, relation: String, address: PostcardMailAddress) async throws -> FridgeMailPlan {
        let a = address.normalized
        return try await planCall(context, .post, "widgets/fridgemail/recipients", body: [
            "name": name, "relation": relation,
            "address": ["line1": a.line1, "line2": a.line2, "city": a.city, "state": a.state, "zip": a.zip]
        ])
    }

    static func removeRecipient(context: WidgetContext, id: String) async throws -> FridgeMailPlan {
        try await planCall(context, .delete, "widgets/fridgemail/recipients/\(id)")
    }

    // MARK: Queue

    static func enqueue(context: WidgetContext, imageURL: URL, childName: String, ageText: String, note: String) async throws -> FridgeMailPlan {
        try await planCall(context, .post, "widgets/fridgemail/queue", body: [
            "imageUrl": imageURL.absoluteString, "childName": childName, "ageText": ageText, "note": note
        ])
    }

    static func removeQueued(context: WidgetContext, id: String) async throws -> FridgeMailPlan {
        try await planCall(context, .delete, "widgets/fridgemail/queue/\(id)")
    }

    static func reorderQueue(context: WidgetContext, ids: [String]) async throws -> FridgeMailPlan {
        try await planCall(context, .put, "widgets/fridgemail/queue/order", body: ["ids": ids])
    }

    // MARK: History

    static func cards(context: WidgetContext) async throws -> [FridgeMailCard] {
        try FridgeMailJSON.decode(CardsResponse.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/fridgemail/cards"))).cards
    }

    // MARK: Money

    /// Buys a pack with Apple Pay. Unlike a single postcard there is no
    /// hold: the pack is paid for on the spot and the credits land on the
    /// plan. Returns nil when the person dismissed the wallet.
    ///
    /// The order is created *inside* the payment sheet (see
    /// `WidgetPaymentRequest.clientSecret`); the client-side `orderId` makes
    /// a retry idempotent. If confirm fails after the wallet succeeded, the
    /// server's Stripe webhook still credits the pack, so the caller
    /// reloads rather than telling the person it failed.
    static func purchasePack(context: WidgetContext, pack: FridgeMailPack, config: PostcardMail.Config,
                             orderId: String = UUID().uuidString) async throws -> FridgeMailPlan? {
        guard let publishableKey = config.publishableKey, let merchantId = config.applePayMerchantId else {
            throw WidgetAPIError(status: 503, message: "Paying for Fridge Mail isn't available yet.")
        }
        let request = WidgetPaymentRequest(
            publishableKey: publishableKey,
            merchantDisplayName: "FavCircles",
            applePayMerchantId: merchantId,
            amountCents: pack.amountCents,
            currency: config.currency,
            summaryLabel: "Fridge Mail · \(pack.label)"
        ) {
            let data = try await context.host.request(WidgetAPIRequest(
                .post, "widgets/fridgemail/packs/orders",
                body: try JSONSerialization.data(withJSONObject: ["orderId": orderId, "packId": pack.id])))
            return try FridgeMailJSON.decode(PackOrderResponse.self, from: data).paymentIntentClientSecret
        }
        guard case .completed = try await context.host.collectPayment(request) else { return nil }
        do {
            return try await planCall(context, .post, "widgets/fridgemail/packs/orders/\(orderId)/confirm")
        } catch {
            return try await plan(context: context)
        }
    }

    /// Starts the monthly subscription with Apple Pay. The wallet confirms
    /// a SetupIntent (no charge in the sheet itself); the server then
    /// creates the subscription against that card and Stripe bills the
    /// first month within seconds. Returns nil when the wallet was dismissed.
    static func subscribe(context: WidgetContext, plan current: FridgeMailPlan, config: PostcardMail.Config) async throws -> FridgeMailPlan? {
        guard let publishableKey = config.publishableKey, let merchantId = config.applePayMerchantId else {
            throw WidgetAPIError(status: 503, message: "Subscribing to Fridge Mail isn't available yet.")
        }
        let quantity = max(1, current.recipients.count)
        let box = SetupBox()
        let request = WidgetPaymentRequest(
            publishableKey: publishableKey,
            merchantDisplayName: "FavCircles",
            applePayMerchantId: merchantId,
            amountCents: current.subscriptionPriceCents * quantity,
            currency: config.currency,
            summaryLabel: quantity == 1
                ? "Fridge Mail · \(PostcardMailOrder.price(cents: current.subscriptionPriceCents))/month"
                : "Fridge Mail · \(quantity) × \(PostcardMailOrder.price(cents: current.subscriptionPriceCents))/month"
        ) {
            let data = try await context.host.request(WidgetAPIRequest(.post, "widgets/fridgemail/subscription/setup"))
            let setup = try FridgeMailJSON.decode(SetupResponse.self, from: data)
            box.setupIntentId = setup.setupIntentId
            return setup.setupIntentClientSecret
        }
        guard case .completed = try await context.host.collectPayment(request) else { return nil }
        return try await planCall(context, .post, "widgets/fridgemail/subscription/start", body: ["setupIntentId": box.setupIntentId])
    }

    static func cancelSubscription(context: WidgetContext) async throws -> FridgeMailPlan {
        try await planCall(context, .post, "widgets/fridgemail/subscription/cancel")
    }

    static func resumeSubscription(context: WidgetContext) async throws -> FridgeMailPlan {
        try await planCall(context, .post, "widgets/fridgemail/subscription/resume")
    }

    // MARK: Plumbing

    /// Carries the SetupIntent id out of the payment closure, which is
    /// `@Sendable` and so can't write to a captured `var`.
    private final class SetupBox: @unchecked Sendable {
        var setupIntentId = ""
    }

    private static func planCall(_ context: WidgetContext, _ method: WidgetAPIRequest.Method, _ path: String,
                                 body: [String: Any]? = nil) async throws -> FridgeMailPlan {
        let response: PlanResponse = try await context.api(method, path, body: body)
        return response.plan
    }
}

/// The in-memory plan shared by the card and the full view, kept in
/// `context.transient` so opening the full view doesn't refetch what the
/// card already has. Server-owned; nothing here is persisted on device.
@MainActor
final class FridgeMailStore: RemoteStore {
    @Published var plan: FridgeMailPlan?
    @Published var cards: [FridgeMailCard] = []
    @Published var config: PostcardMail.Config?

    static func shared(_ context: WidgetContext) -> FridgeMailStore {
        context.transient("fridgemail.store") { FridgeMailStore() }
    }

    /// The card needs only the plan.
    func loadIfNeeded(context: WidgetContext) async {
        await loadIfNeeded { self.plan = try await FridgeMailAPI.plan(context: context) }
    }

    func load(context: WidgetContext) async {
        await load { self.plan = try await FridgeMailAPI.plan(context: context) }
        await loadDetails(context: context)
    }

    /// History and the Stripe keys, wanted only by the full view; neither
    /// stops the plan from showing.
    func loadDetails(context: WidgetContext) async {
        async let history = try? FridgeMailAPI.cards(context: context)
        async let keys = try? PostcardMail.config(context: context)
        if let history = await history { cards = history }
        if let keys = await keys { config = keys }
    }

    func apply(_ plan: FridgeMailPlan) {
        self.plan = plan
        markLoaded()
    }
}

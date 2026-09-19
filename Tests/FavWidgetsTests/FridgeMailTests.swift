import Testing
import Foundation
@testable import FavWidgets
@testable import FavWidgetsCore

@MainActor
struct FridgeMailTests {
    private static let planJSON = """
    {"success":true,"plan":{"familyName":"","recipients":[{"id":"r1","name":"Sue","relation":"Grandma","address":{"line1":"1 Main St","line2":"","city":"Austin","state":"TX","zip":"78701"}}],
     "queue":[],"weekday":1,"timezone":"America/Chicago","status":"active","cardsRemaining":5,"subscription":null,
     "lastSentAt":null,"nextSendAt":null,"entitlement":{"covered":1,"recipients":1,"subscribedSlots":0,"weeksOfCredits":5},
     "packs":[{"id":"pack5","cards":5,"amountCents":1299,"label":"5 cards"}],"subscriptionPriceCents":799,"currency":"usd"}}
    """
    private static let configJSON = """
    {"enabled":true,"priceCents":299,"currency":"usd","cancelWindowMinutes":60,"messageMaxChars":300,"publishableKey":"pk_test","applePayMerchantId":"merchant.test"}
    """

    private func makeContext(host: MockWidgetHost) -> WidgetContext {
        WidgetsTabModel(host: host).context(for: FridgeMailWidget().descriptor)
    }

    private func config() throws -> PostcardMail.Config {
        try JSONDecoder().decode(PostcardMail.Config.self, from: Data(Self.configJSON.utf8))
    }

    @Test func registryHasFridgeMail() {
        let descriptor = FavWidgetRegistry.widget(id: "fridgemail")?.descriptor
        #expect(descriptor?.category == .social)
        #expect(descriptor?.storage == .single)
    }

    @Test func packIsCreatedInsideTheSheetThenConfirmed() async throws {
        let host = MockWidgetHost()
        host.apiResponses["POST widgets/fridgemail/packs/orders"] = Data("""
        {"success":true,"orderId":"o1","paymentIntentClientSecret":"pi_1_secret_x","amountCents":1299,"cards":5}
        """.utf8)
        host.apiResponses["POST widgets/fridgemail/packs/orders/o1/confirm"] = Data(Self.planJSON.utf8)
        let context = makeContext(host: host)
        let pack = FridgeMailPack(id: "pack5", cards: 5, amountCents: 1299, label: "5 cards")

        let plan = try await FridgeMailAPI.purchasePack(context: context, pack: pack, config: try config(), orderId: "o1")

        #expect(plan?.cardsRemaining == 5)
        #expect(host.paymentRequests.first?.amountCents == 1299)
        #expect(host.paymentRequests.first?.summaryLabel == "Fridge Mail · 5 cards")
        #expect(host.collectedClientSecrets == ["pi_1_secret_x"])
        // Order creation happened after the wallet, not before it.
        #expect(host.apiRequests.map(\.path) == ["widgets/fridgemail/packs/orders", "widgets/fridgemail/packs/orders/o1/confirm"])
        let body = try #require(host.apiRequests.first?.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["orderId"] as? String == "o1")
        #expect(json["packId"] as? String == "pack5")
    }

    @Test func dismissedWalletBuysNothing() async throws {
        let host = MockWidgetHost()
        host.paymentResult = .canceled
        let context = makeContext(host: host)
        let pack = FridgeMailPack(id: "pack5", cards: 5, amountCents: 1299, label: "5 cards")
        let plan = try await FridgeMailAPI.purchasePack(context: context, pack: pack, config: try config())
        #expect(plan == nil)
        #expect(host.apiRequests.isEmpty)
    }

    @Test func confirmFailureFallsBackToReloadingThePlan() async throws {
        let host = MockWidgetHost()
        host.apiResponses["POST widgets/fridgemail/packs/orders"] = Data("""
        {"success":true,"orderId":"o2","paymentIntentClientSecret":"pi_2_secret","amountCents":1299,"cards":5}
        """.utf8)
        host.apiResponses["GET widgets/fridgemail/plan"] = Data(Self.planJSON.utf8)
        let context = makeContext(host: host)
        let pack = FridgeMailPack(id: "pack5", cards: 5, amountCents: 1299, label: "5 cards")
        let plan = try await FridgeMailAPI.purchasePack(context: context, pack: pack, config: try config(), orderId: "o2")
        #expect(plan?.cardsRemaining == 5)
        #expect(host.apiRequests.last?.path == "widgets/fridgemail/plan")
    }

    @Test func subscribeSetsUpInsideTheSheetThenStartsWithThatIntent() async throws {
        let host = MockWidgetHost()
        host.apiResponses["POST widgets/fridgemail/subscription/setup"] = Data("""
        {"success":true,"setupIntentId":"seti_9","setupIntentClientSecret":"seti_9_secret","priceCents":799,"quantity":1}
        """.utf8)
        host.apiResponses["POST widgets/fridgemail/subscription/start"] = Data(Self.planJSON.replacingOccurrences(
            of: "\"subscription\":null", with: "\"subscription\":{\"status\":\"active\",\"quantity\":1,\"currentPeriodEnd\":\"2026-10-18T15:00:00Z\",\"cancelAtPeriodEnd\":false}").utf8)
        let context = makeContext(host: host)
        let current = try FridgeMailJSON.decode(Envelope.self, from: Data(Self.planJSON.utf8)).plan

        let plan = try await FridgeMailAPI.subscribe(context: context, plan: current, config: try config())

        #expect(plan?.isSubscribed == true)
        #expect(host.paymentRequests.first?.amountCents == 799)
        #expect(host.paymentRequests.first?.summaryLabel == "Fridge Mail · $7.99/month")
        #expect(host.collectedClientSecrets == ["seti_9_secret"])
        let start = try #require(host.apiRequests.last)
        #expect(start.path == "widgets/fridgemail/subscription/start")
        let startBody = try #require(start.body)
        let json = try #require(JSONSerialization.jsonObject(with: startBody) as? [String: Any])
        #expect(json["setupIntentId"] as? String == "seti_9")
    }

    @Test func subscriptionAmountScalesWithGrandparents() async throws {
        let host = MockWidgetHost()
        host.paymentResult = .canceled
        let context = makeContext(host: host)
        var current = try FridgeMailJSON.decode(Envelope.self, from: Data(Self.planJSON.utf8)).plan
        current.recipients.append(FridgeMailRecipient(id: "r2", name: "Joe", address: PostcardMailAddress(name: "Joe")))
        _ = try await FridgeMailAPI.subscribe(context: context, plan: current, config: try config())
        #expect(host.paymentRequests.first?.amountCents == 1598)
        #expect(host.paymentRequests.first?.summaryLabel == "Fridge Mail · 2 × $7.99/month")
    }

    @Test func storeLoadsPlanHistoryAndKeys() async throws {
        let host = MockWidgetHost()
        host.apiResponses["GET widgets/fridgemail/plan"] = Data(Self.planJSON.utf8)
        host.apiResponses["GET widgets/fridgemail/cards"] = Data("""
        {"success":true,"cards":[{"cardId":"c1","status":"submitted","recipientId":"r1","recipientName":"Sue","childName":"Maya","note":"","imageUrl":"https://x/1.jpg","expectedDeliveryDate":"2026-09-24","lobLastEvent":null,"createdAt":"2026-09-14T15:00:00.000Z"}]}
        """.utf8)
        host.apiResponses["GET widgets/postcard/mail/config"] = Data(Self.configJSON.utf8)
        let context = makeContext(host: host)
        let store = FridgeMailStore.shared(context)
        await store.loadIfNeeded(context: context)
        #expect(store.plan?.recipients.count == 1)
        #expect(store.cards.count == 1)
        #expect(store.config?.isUsable == true)
        #expect(store.loadError == nil)
        // Same object for the card and the full view.
        #expect(FridgeMailStore.shared(context) === store)
    }

    private struct Envelope: Decodable { let plan: FridgeMailPlan }
}

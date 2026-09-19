import Testing
import Foundation
@testable import FavWidgetsCore

struct FridgeMailModelTests {
    static let fixture = """
    {"success":true,"plan":{
      "familyName":"the Sgrois",
      "recipients":[{"id":"r1","name":"Sue","relation":"Grandma","address":{"line1":"1540 S CHURCH ST","line2":"STE G","city":"CHARLOTTE","state":"NC","zip":"28203"}}],
      "queue":[
        {"id":"q1","imageUrl":"https://storage.googleapis.com/b/one.jpg","childName":"Maya","ageText":"4","note":"Our dog","addedAt":"2026-09-18T14:02:11.123Z","sentAt":null},
        {"id":"q0","imageUrl":"https://storage.googleapis.com/b/zero.jpg","childName":"Maya","ageText":"","note":"","addedAt":"2026-09-10T14:02:11Z","sentAt":"2026-09-14T15:00:00Z"}
      ],
      "weekday":1,"timezone":"America/New_York","status":"active","cardsRemaining":5,
      "subscription":{"status":"active","quantity":1,"currentPeriodEnd":"2026-10-18T15:00:00.000Z","cancelAtPeriodEnd":false},
      "lastSentAt":"2026-09-14T15:00:00.000Z","nextSendAt":"2026-09-21T15:00:00.000Z",
      "entitlement":{"covered":1,"recipients":1,"subscribedSlots":1,"weeksOfCredits":null},
      "packs":[{"id":"pack5","cards":5,"amountCents":1299,"label":"5 cards"}],
      "subscriptionPriceCents":799,"currency":"usd"}}
    """

    private struct Envelope: Decodable { let plan: FridgeMailPlan }

    static var plan: FridgeMailPlan {
        try! FridgeMailJSON.decode(Envelope.self, from: Data(fixture.utf8)).plan
    }

    @Test func decodesTheServerShape() throws {
        let plan = Self.plan
        #expect(plan.recipients.first?.displayName == "Grandma Sue")
        #expect(plan.recipients.first?.address.name == "Sue")
        #expect(plan.recipients.first?.address.oneLine == "1540 S CHURCH ST, STE G, CHARLOTTE NC 28203")
        #expect(plan.pending.map(\.id) == ["q1"])
        #expect(plan.nextItem?.note == "Our dog")
        #expect(plan.isSubscribed)
        #expect(plan.subscription?.currentPeriodEnd != nil)
        #expect(plan.entitlement.weeksOfCredits == nil)
        #expect(plan.packs.first?.perCardText == "$2.60 a card")
        #expect(!plan.isEmpty)
    }

    @Test func unknownCardStatusNeverBreaksDecoding() throws {
        let json = """
        {"cards":[{"cardId":"c1","status":"something_new","recipientName":"Sue","childName":"Maya","note":"","imageUrl":null,"expectedDeliveryDate":null,"lobLastEvent":null,"createdAt":"2026-09-14T15:00:00.000Z"}]}
        """
        struct Cards: Decodable { let cards: [FridgeMailCard] }
        let cards = try FridgeMailJSON.decode(Cards.self, from: Data(json.utf8)).cards
        #expect(cards.first?.status == .unknown)
        #expect(FridgeMailCopy.cardStatus(.unknown, recipientName: "Sue") == "Sent to Sue")
    }

    @Test func cardSummaryLeadsWithWhatToDoNext() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        #expect(FridgeMailCopy.cardSummary(nil, calendar: cal) == "Kids' drawings, mailed to Grandma every week")

        var plan = Self.plan
        #expect(FridgeMailCopy.cardSummary(plan, calendar: cal) == "Next card Monday · 1 queued · subscribed")

        plan.subscription = nil
        plan.entitlement = FridgeMailEntitlement(covered: 1, recipients: 1, subscribedSlots: 0, weeksOfCredits: 5)
        #expect(FridgeMailCopy.cardSummary(plan, calendar: cal) == "Next card Monday · 1 queued · 5 cards left")

        plan.cardsRemaining = 0
        plan.entitlement = FridgeMailEntitlement(covered: 0, recipients: 1, subscribedSlots: 0, weeksOfCredits: 0)
        #expect(FridgeMailCopy.cardSummary(plan, calendar: cal) == "Out of cards · 1 queued")

        plan.queue = []
        #expect(FridgeMailCopy.cardSummary(plan, calendar: cal) == "Add a drawing · nothing queued for Monday")

        plan.recipients = []
        plan.cardsRemaining = 5
        #expect(FridgeMailCopy.cardSummary(plan, calendar: cal) == "Add a grandparent to start mailing")

        // Nothing at all yet: the tagline, not a to-do.
        plan.cardsRemaining = 0
        #expect(FridgeMailCopy.cardSummary(plan, calendar: cal) == "Kids' drawings, mailed to Grandma every week")
    }

    @Test func planStatusExplainsSubscriptionAndCredits() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "UTC")!
        var plan = Self.plan
        #expect(FridgeMailCopy.planStatus(plan, calendar: cal) == "Subscribed · 1 grandparent · renews Oct 18\n5 prepaid cards")

        plan.subscription?.cancelAtPeriodEnd = true
        #expect(FridgeMailCopy.planStatus(plan, calendar: cal).hasPrefix("Subscription ends Oct 18"))

        plan.subscription = nil
        plan.entitlement.weeksOfCredits = 5
        #expect(FridgeMailCopy.planStatus(plan, calendar: cal) == "5 prepaid cards · about 5 weeks")

        plan.cardsRemaining = 0
        #expect(FridgeMailCopy.planStatus(plan, calendar: cal) == "No cards yet")
    }

    @Test func nextSendLineWarnsWhenNotEveryoneIsCovered() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        var plan = Self.plan
        plan.recipients.append(FridgeMailRecipient(id: "r2", name: "Joe", relation: "Grandpa", address: PostcardMailAddress(name: "Joe")))
        plan.entitlement = FridgeMailEntitlement(covered: 1, recipients: 2, subscribedSlots: 1, weeksOfCredits: 0)
        #expect(FridgeMailCopy.nextSendLine(plan, calendar: cal) == "Goes to 1 of 2 grandparents Monday — add cards to cover everyone")

        plan.entitlement.covered = 0
        #expect(FridgeMailCopy.nextSendLine(plan, calendar: cal).hasPrefix("Needs cards"))

        plan.status = "paused"
        #expect(FridgeMailCopy.nextSendLine(plan, calendar: cal).hasPrefix("Paused"))
    }

    @Test func backCopy() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_789_000_000) // 2026-09-09 UTC
        #expect(FridgeMailCopy.backHeadline(childName: "Maya", ageText: "4", date: date, calendar: cal) == "Maya, age 4 · September 9, 2026")
        #expect(FridgeMailCopy.backHeadline(childName: "", ageText: "", date: date, calendar: cal) == "Made with love · September 9, 2026")
        #expect(FridgeMailCopy.signature(familyName: "the Sgrois") == "— From the Sgrois")
        #expect(FridgeMailCopy.signature(familyName: " ") == "— With love")
    }

    @Test func weekdayUsesTheJavaScriptConvention() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        #expect(FridgeMailCopy.weekdayName(0, calendar: cal) == "Sunday")
        #expect(FridgeMailCopy.weekdayName(6, calendar: cal) == "Saturday")
        #expect(FridgeMailCopy.weekdayName(9, calendar: cal) == "Monday")
    }

    // MARK: Layout

    @Test func portraitDrawingIsNeverCropped() {
        let canvas = CGSize(width: 625, height: 425)
        let rect = FridgeMailLayout.fit(image: CGSize(width: 3000, height: 4000), canvas: canvas, inset: 38.5, stripHeight: 44)
        // Height-bound: fills the available height, keeps 3:4, centered.
        #expect(abs(rect.height - (425 - 77 - 44)) < 0.01)
        #expect(abs(rect.width / rect.height - 0.75) < 0.001)
        #expect(abs(rect.midX - 312.5) < 0.01)
        #expect(rect.minY >= 38.5 && rect.maxY <= 425 - 38.5 - 44)
    }

    @Test func wideDrawingIsWidthBound() {
        let canvas = CGSize(width: 625, height: 425)
        let rect = FridgeMailLayout.fit(image: CGSize(width: 4000, height: 1000), canvas: canvas, inset: 38.5, stripHeight: 0)
        #expect(abs(rect.width - (625 - 77)) < 0.01)
        #expect(abs(rect.width / rect.height - 4) < 0.001)
        #expect(rect.minX >= 38.5 && rect.maxX <= 625 - 38.5)
    }

    @Test func degenerateImageFillsTheFrame() {
        let rect = FridgeMailLayout.fit(image: .zero, canvas: CGSize(width: 100, height: 60), inset: 10, stripHeight: 0)
        #expect(rect == CGRect(x: 10, y: 10, width: 80, height: 40))
    }
}

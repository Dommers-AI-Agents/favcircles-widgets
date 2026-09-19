import Testing
import Foundation
@testable import FavWidgetsCore

/// The mail leg's device-side rules. These decide whether someone is even
/// offered the chance to spend money, and what they're told afterwards.
struct PostcardMailAddressTests {
    private func address(
        name: String = "Ana Ruiz", line1: String = "123 Main St", line2: String = "",
        city: String = "Austin", state: String = "TX", zip: String = "78701"
    ) -> PostcardMailAddress {
        PostcardMailAddress(name: name, line1: line1, line2: line2, city: city, state: state, zip: zip)
    }

    @Test func acceptsAnOrdinaryAddress() {
        #expect(address().isComplete)
    }

    @Test func lowercaseStateIsNormalizedRatherThanRejected() {
        // People type "tx". Refusing that would be pedantry, not validation.
        #expect(address(state: "tx").isComplete)
        #expect(address(state: " tx ").normalized.state == "TX")
    }

    @Test func requiresEveryPartTheMailNeeds() {
        #expect(!address(name: "").isComplete)
        #expect(!address(line1: "").isComplete)
        #expect(!address(city: "").isComplete)
        #expect(!address(state: "ZZ").isComplete)
    }

    @Test func acceptsZipPlusFourButNotShorterZips() {
        #expect(address(zip: "78701-1234").isComplete)
        #expect(!address(zip: "7870").isComplete)
        #expect(!address(zip: "abcde").isComplete)
    }

    @Test func territoriesCanReceiveMail() {
        // Puerto Rico and the Virgin Islands are domestic US mail; dropping
        // them would silently exclude real customers.
        #expect(address(state: "PR", zip: "00901").isComplete)
        #expect(address(state: "VI", zip: "00802").isComplete)
    }

    @Test func oneLineReadsLikeAnAddress() {
        #expect(address().oneLine == "123 Main St, Austin TX 78701")
        #expect(address(line2: "Apt 4").oneLine == "123 Main St, Apt 4, Austin TX 78701")
    }
}

struct PostcardMailStatusTests {
    @Test func onlyAnAuthorizedOrderCanBeCanceled() {
        // Anything further along may already be at the printer, and offering
        // Cancel there would void a hold on a card that still gets mailed.
        #expect(PostcardMailStatus.authorized.isCancelable)
        #expect(!PostcardMailStatus.submitting.isCancelable)
        #expect(!PostcardMailStatus.submitted.isCancelable)
        #expect(!PostcardMailStatus.delivered.isCancelable)
    }

    @Test func anUnfamiliarServerStatusDoesNotBreakAnOldBuild() throws {
        let decoded = try JSONDecoder().decode(PostcardMailStatus.self, from: Data("\"some_new_thing\"".utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.isCancelable)
    }

    @Test func knownStatusesStillDecode() throws {
        let decoded = try JSONDecoder().decode(PostcardMailStatus.self, from: Data("\"in_transit\"".utf8))
        #expect(decoded == .inTransit)
    }
}

struct PostcardMailOrderDisplayTests {
    private func order(_ status: PostcardMailStatus, delivery: String? = nil) -> PostcardMailOrder {
        PostcardMailOrder(orderId: "o1", status: status, priceCents: 399,
                          recipientName: "Ana", expectedDeliveryDate: delivery)
    }

    @Test func aHeldOrderLeadsWithTheMoneyPosition() {
        // "Am I charged?" is the question someone actually has in that hour.
        #expect(order(.authorized).displayStatus.contains("not charged until it prints"))
    }

    @Test func everyFreeOutcomeSaysSoPlainly() {
        #expect(order(.canceled).displayStatus.contains("weren't charged"))
        #expect(order(.rejected).displayStatus.contains("weren't charged"))
        #expect(order(.expired).displayStatus.contains("weren't charged"))
    }

    @Test func aMailedCardShowsWhenItArrives() {
        // Lob's date is an outer bound; the row states the typical window instead
        #expect(order(.submitted, delivery: "2026-09-20").displayStatus.contains("typically arrives in 4 to 6 business days"))
        #expect(!order(.submitted, delivery: "2026-09-20").displayStatus.contains("Sep 20"))
        #expect(order(.inTransit, delivery: nil).displayStatus.hasPrefix("In the mail"))
    }

    @Test func anUnparseableDateIsOmittedRatherThanEchoed() {
        #expect(PostcardMailOrder.friendlyDate("not a date") == nil)
        #expect(PostcardMailOrder.friendlyDate(nil) == nil)
        #expect(!order(.submitted, delivery: "garbage").displayStatus.contains("garbage"))
    }

    @Test func priceReadsAsMoney() {
        #expect(PostcardMailOrder.price(cents: 399).contains("3.99"))
        #expect(PostcardMailOrder.price(cents: 1000).contains("10"))
    }

    @Test func aRecordWrittenBeforeMailExistedStillDecodes() throws {
        // PostcardRecord.mailOrder was added in 0.5.0; history saved by an
        // earlier build has no such key and must not fail to load.
        let json = """
        {"id":"\(UUID().uuidString)","messageId":"m1","conversationId":"c1","recipientId":"u1",
         "recipientName":"Ana","templateId":"classic","message":"hi","sentAt":0}
        """
        let record = try JSONDecoder().decode(PostcardRecord.self, from: Data(json.utf8))
        #expect(record.mailOrder == nil)
        #expect(record.recipientName == "Ana")
    }
}

// App Review typed a ten-digit number into ZIP, got a greyed-out Send and the
// sentence "Fill in the mailing address" — with every field visibly full — and
// rejected the build as an unresponsive button. The hint has to name the field.
@Suite("Address problems are named, not generalised")
struct PostcardMailAddressProblemTests {
    private func address(name: String = "Ana Ruiz", line1: String = "1 Apple Park Way",
                         city: String = "Cupertino", state: String = "CA",
                         zip: String = "95014") -> PostcardMailAddress {
        PostcardMailAddress(name: name, line1: line1, city: city, state: state, zip: zip)
    }

    @Test func aGoodAddressHasNoProblem() {
        #expect(address().firstProblem == nil)
        #expect(address().isComplete)
    }

    @Test func theExactAddressAppleReviewTypedNamesTheZip() {
        // Their screenshot: name "hnhhu", "1 apple Park Way", Cupertino, DE,
        // zip 6693334444. Everything present; only the ZIP is wrong.
        let theirs = address(name: "hnhhu", line1: "1 apple Park Way",
                             city: "Cupertino", state: "DE", zip: "6693334444")
        #expect(theirs.isComplete == false)
        let problem = theirs.firstProblem
        #expect(problem != nil)
        #expect(problem?.contains("ZIP") == true)
        // The old message said this, and it was not true of their screen.
        #expect(problem != "Fill in the mailing address.")
    }

    @Test func eachMissingFieldNamesItself() {
        #expect(address(name: "").firstProblem?.contains("name") == true)
        #expect(address(line1: "").firstProblem?.contains("street") == true)
        #expect(address(city: "").firstProblem?.contains("city") == true)
        #expect(address(state: "").firstProblem?.contains("state") == true)
        #expect(address(zip: "").firstProblem?.contains("ZIP") == true)
    }

    @Test func aZipPlusFourIsStillFine() {
        #expect(address(zip: "95014-2084").isComplete)
    }

    @Test func problemsAreReportedInReadingOrder() {
        // Everything wrong at once: the person is told about the first field
        // they'd look at, not the last.
        let empty = address(name: "", line1: "", city: "", state: "", zip: "")
        #expect(empty.firstProblem?.contains("name") == true)
    }
}

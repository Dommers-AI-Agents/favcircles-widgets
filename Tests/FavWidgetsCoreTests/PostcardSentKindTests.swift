import Foundation
import Testing
@testable import FavWidgetsCore

@Suite("Sent postcards: mailed, in the app or email")
struct PostcardSentKindTests {
    private func record(_ messageId: String, recipientId: String = "u1", imageURL: String? = nil,
                        order: PostcardMailOrder? = nil) -> PostcardRecord {
        PostcardRecord(messageId: messageId, conversationId: "", recipientId: recipientId, recipientName: "Linda",
                       templateId: "classic", message: "", imageURL: imageURL.flatMap(URL.init(string:)), place: nil,
                       mailOrder: order)
    }
    private let order = PostcardMailOrder(orderId: "o1", status: .inTransit, priceCents: 199, recipientName: "Linda",
                                          imageUrl: "https://img.example/card.jpg")

    @Test func kinds() {
        #expect(record("mail:o1", recipientId: "mail", order: order).sentKind == .mailed)
        #expect(record("mail:o1", recipientId: "mail").sentKind == .mailed)
        #expect(record("email:x", recipientId: "email", imageURL: "https://favcircles.com/p/abc").sentKind == .email)
        #expect(record("m123", imageURL: "https://img.example/a.jpg").sentKind == .app)
    }

    @Test func mailedCardShowsTheOrdersPicture() {
        #expect(record("mail:o1", recipientId: "mail", order: order).cardImageURL?.absoluteString == "https://img.example/card.jpg")
    }

    @Test func emailRecordIsAPageNotAPicture() {
        let r = record("email:x", recipientId: "email", imageURL: "https://favcircles.com/p/abc")
        #expect(r.cardImageURL == nil)
        #expect(r.cardPageURL?.absoluteString == "https://favcircles.com/p/abc")
    }

    @Test func filter() {
        let mailed = record("mail:o1", recipientId: "mail", order: order)
        let chat = record("m1")
        let email = record("email:x", recipientId: "email")
        #expect(PostcardSentFilter.mailed.includes(mailed) && !PostcardSentFilter.mailed.includes(chat))
        #expect(PostcardSentFilter.digital.includes(chat) && PostcardSentFilter.digital.includes(email) && !PostcardSentFilter.digital.includes(mailed))
        #expect([mailed, chat, email].allSatisfy(PostcardSentFilter.all.includes))
    }
}

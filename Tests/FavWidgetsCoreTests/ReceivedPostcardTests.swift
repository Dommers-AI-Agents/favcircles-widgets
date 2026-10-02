import Testing
import Foundation
@testable import FavWidgetsCore

struct ReceivedPostcardTests {
    private func card(isMine: Bool = false, connected: Bool = true, place: String? = nil, city: String? = nil) -> ReceivedPostcard {
        ReceivedPostcard(token: "abcdefghijklmnopqrst", senderId: "wes", senderName: "Wesley", imageUrl: "https://x/card.jpg",
                         message: "Hope you are having a lovely day!!", placeName: place, placeCity: city,
                         createdAt: "2026-09-18T13:21:08.699Z", isMine: isMine, senderIsConnection: connected)
    }

    @Test func decodesTheServerShape() throws {
        let json = #"{"token":"abcdefghijklmnopqrst","senderId":"wes","senderName":"Wesley","imageUrl":"https://x/card.jpg","message":"hi","placeName":null,"placeCity":null,"createdAt":"2026-09-18T13:21:08Z","isMine":false,"senderIsConnection":true}"#
        let decoded = try JSONDecoder().decode(ReceivedPostcard.self, from: Data(json.utf8))
        #expect(decoded.senderName == "Wesley" && decoded.senderIsConnection && decoded.placeName == nil)
    }

    @Test func friendSeesSendOneBackAddressedToTheSender() {
        let c = card()
        #expect(ReceivedPostcardCopy.title(c) == "A postcard from Wesley")
        #expect(ReceivedPostcardCopy.primaryButton(c) == "Send one back")
        #expect(ReceivedPostcardCopy.sendHint(c) == "It'll be addressed to Wesley.")
        let us = Locale(identifier: "en_US"), ny = TimeZone(identifier: "America/New_York")!
        #expect(ReceivedPostcardCopy.byline(c, locale: us, timeZone: ny) == "— Wesley · September 18, 2026")
    }

    @Test func nonConnectionAndOwnCard() {
        #expect(ReceivedPostcardCopy.sendHint(card(connected: false)).hasPrefix("Make one"))
        let mine = card(isMine: true, connected: false)
        #expect(ReceivedPostcardCopy.title(mine) == "Your postcard")
        #expect(ReceivedPostcardCopy.primaryButton(mine) == "Send another")
        #expect(ReceivedPostcardCopy.byline(mine, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).hasPrefix("— You · "))
    }

    @Test func placeLine() {
        #expect(ReceivedPostcardCopy.place(card()) == nil)
        #expect(ReceivedPostcardCopy.place(card(place: "Midnight Diner")) == "From Midnight Diner")
        #expect(ReceivedPostcardCopy.place(card(place: "Midnight Diner", city: "Charlotte")) == "From Midnight Diner, Charlotte")
    }
}

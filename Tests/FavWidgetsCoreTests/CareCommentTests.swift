import Testing
import Foundation
@testable import FavWidgetsCore

struct CareCommentTests {
    private func decode(_ json: String) throws -> CareAsk {
        try WidgetJSON.decode(CareAsk.self, from: Data(json.utf8))
    }

    @Test func commentsDecodeOldestFirstAndOlderServersHaveNone() throws {
        let ask = try decode(#"{"askId":"a","planId":"p","questionText":"Sleep?","kind":"scale","askedAt":"2026-10-08T12:30:00.000Z","status":"answered","answerText":"6/10","comments":[{"id":"c1","userId":"wes","name":"Wes","text":"Rest up","at":"2026-10-08T13:00:00.000Z"}]}"#)
        #expect(ask.comments.map(\.text) == ["Rest up"])
        #expect(ask.comments.first?.at != nil)
        let old = try decode(#"{"askId":"a","planId":"p","questionText":"Sleep?","askedAt":"2026-10-08T12:30:00.000Z"}"#)
        #expect(old.comments.isEmpty)
    }
}

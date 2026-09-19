import Testing
import Foundation
@testable import FavWidgets
@testable import FavWidgetsCore

struct PostcardEmailParsingTests {
    @Test func parsesAndValidatesAddresses() {
        let parsed = PostcardEmail.parse(" Ana@Example.com, bob@example.org; ana@example.com nope@x  ")
        #expect(parsed.valid == ["ana@example.com", "bob@example.org"])
        #expect(parsed.invalid == ["nope@x"])
        #expect(PostcardEmail.parse("").valid.isEmpty)
        #expect(!PostcardEmail.isValid("a@b"))
        #expect(PostcardEmail.isValid("wes@favcircles.com"))
    }
}

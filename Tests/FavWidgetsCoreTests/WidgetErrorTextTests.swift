import XCTest
@testable import FavWidgetsCore

final class WidgetErrorTextTests: XCTestCase {
    func testCancellationsAreNotShown() {
        XCTAssertNil(WidgetErrorText.message(for: CancellationError()))
        XCTAssertNil(WidgetErrorText.message(for: URLError(.cancelled)))
        XCTAssertNil(WidgetErrorText.message(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
    }

    func testOfflineReadsAsAnAction() {
        XCTAssertEqual(WidgetErrorText.message(for: URLError(.notConnectedToInternet)), "Couldn't connect. Pull down to try again.")
    }

    func testServerMessageWins() {
        XCTAssertEqual(WidgetErrorText.message(for: WidgetAPIError(status: 403, message: "Join the event to see it")), "Join the event to see it")
    }

    func testNoRawSystemStrings() {
        XCTAssertEqual(WidgetErrorText.message(for: NSError(domain: "x", code: 1)), "Something went wrong. Pull down to try again.")
    }
}

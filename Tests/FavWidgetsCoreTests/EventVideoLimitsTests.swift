import XCTest
@testable import FavWidgetsCore

/// Event videos (2026-10-10): free 15 s × 5, Premium 60 s × 20.
final class EventVideoLimitsTests: XCTestCase {
    let free = EventVideoLimits(isPremium: false, maxSeconds: 15, perEvent: 5, used: 0)
    let premium = EventVideoLimits(isPremium: true, maxSeconds: 60, perEvent: 20, used: 0)

    func testFreeShortClipIsFine() {
        XCTAssertEqual(free.verdict(durations: [15.2]), .ok)
    }

    func testFreeLongClipOffersPremium() {
        XCTAssertEqual(free.verdict(durations: [30]), .tooLong(maxSeconds: 15, upgrade: true))
    }

    func testFreeTooLongEvenForPremiumDoesNotUpsell() {
        XCTAssertEqual(free.verdict(durations: [90]), .tooLong(maxSeconds: 15, upgrade: false))
    }

    func testPremiumMinute() {
        XCTAssertEqual(premium.verdict(durations: [60]), .ok)
        XCTAssertEqual(premium.verdict(durations: [61]), .tooLong(maxSeconds: 60, upgrade: false))
    }

    func testFreeCountCap() {
        let used = EventVideoLimits(isPremium: false, maxSeconds: 15, perEvent: 5, used: 5)
        XCTAssertEqual(used.verdict(durations: [5]), .tooMany(allowed: 0, upgrade: true))
        let four = EventVideoLimits(isPremium: false, maxSeconds: 15, perEvent: 5, used: 4)
        XCTAssertEqual(four.verdict(durations: [5, 5]), .tooMany(allowed: 1, upgrade: true))
    }

    func testPremiumHardCap() {
        let used = EventVideoLimits(isPremium: true, maxSeconds: 60, perEvent: 20, used: 20)
        XCTAssertEqual(used.verdict(durations: [5]), .tooMany(allowed: 0, upgrade: false))
    }

    func testVideoDecodesAndOldPhotoStillDecodes() throws {
        let json = #"{"id":"v","imageUrl":"p.jpg","uploaderId":"u","uploaderName":"U","caption":"","likeCount":0,"likedByMe":false,"canDelete":true,"kind":"video","videoUrl":"v.mp4","durationSec":12.4}"#
        let v = try JSONDecoder().decode(EventPhoto.self, from: Data(json.utf8))
        XCTAssertTrue(v.isVideo)
        XCTAssertEqual(v.durationLabel, "0:12")
        let photo = #"{"id":"p","imageUrl":"p.jpg","uploaderId":"u","uploaderName":"U","caption":"","likeCount":0,"likedByMe":false,"canDelete":true}"#
        XCTAssertFalse(try JSONDecoder().decode(EventPhoto.self, from: Data(photo.utf8)).isVideo)
    }
}

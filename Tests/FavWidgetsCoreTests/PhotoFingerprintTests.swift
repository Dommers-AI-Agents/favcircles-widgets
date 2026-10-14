import XCTest
@testable import FavWidgetsCore

final class PhotoFingerprintTests: XCTestCase {
    private func gradient(_ step: Int) -> [UInt8] {
        (0..<(PhotoFingerprint.width * PhotoFingerprint.height)).map { UInt8(($0 % 9) * step) }
    }

    func testSixteenHexCharactersAndStable() throws {
        let h = try XCTUnwrap(PhotoFingerprint.hash(luma: gradient(20)))
        XCTAssertEqual(h.count, 16)
        XCTAssertEqual(h, PhotoFingerprint.hash(luma: gradient(20)))
        XCTAssertTrue(h.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    func testRisingAndFallingPicturesDiffer() {
        // Rising left to right: no pixel is brighter than its neighbour
        XCTAssertEqual(PhotoFingerprint.hash(luma: gradient(20)), "0000000000000000")
        let falling = Array((0..<72).map { UInt8(200 - ($0 % 9) * 20) })
        XCTAssertEqual(PhotoFingerprint.hash(luma: falling), "ffffffffffffffff")
    }

    func testSmallBrightnessShiftKeepsTheHash() {
        let a = gradient(10).map { UInt8(min(255, Int($0) + 40)) }
        XCTAssertEqual(PhotoFingerprint.hash(luma: a), PhotoFingerprint.hash(luma: gradient(10)))
    }

    func testWrongSizeIsNil() {
        XCTAssertNil(PhotoFingerprint.hash(luma: [1, 2, 3]))
    }
}

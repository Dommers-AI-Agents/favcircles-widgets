import Testing
import Foundation
@testable import FavWidgetsCore

struct CarrierDetectorTests {
    @Test(arguments: [
        ("1Z999AA10123456784", Carrier.ups),
        ("1z 999 aa1 01 2345 6784", .ups),
        ("T1234567890", .ups),
        ("9400111899223197428490", .usps),
        ("9205 5000 0000 0000 0000 00", .usps),
        ("EA123456789US", .usps),
        ("420902109400111899223197428490", .usps),
        ("123456789012", .fedex),
        ("123456789012345", .fedex),
        ("9612019123456789012345", .fedex),  // FedEx Ground 96…
        ("12345678901234567890", .fedex),
        ("TBA123456789000", .amazon),
        ("1234567890", .dhl),
        ("JJD0123456789012345678", .dhl),
        ("C12345678901234", .ontrac),
        ("hello", .other)
    ])
    func detects(_ number: String, _ carrier: Carrier) {
        #expect(CarrierDetector.detect(number) == carrier)
    }

    @Test func normalizesAndBuildsURLs() {
        #expect(CarrierDetector.normalize(" 1z-999 aa1 ") == "1Z999AA1")
        #expect(Carrier.ups.trackingURL("1Z999AA10123456784")?.absoluteString == "https://www.ups.com/track?tracknum=1Z999AA10123456784")
        #expect(Carrier.usps.trackingURL("9400111899223197428490")?.host == "tools.usps.com")
        #expect(Carrier.other.trackingURL("XYZ123")?.host == "www.google.com")
    }

    @Test func clipboardCheck() {
        #expect(CarrierDetector.looksLikeTrackingNumber("1Z999AA10123456784"))
        #expect(CarrierDetector.looksLikeTrackingNumber("9400 1118 9922 3197 4284 90"))
        #expect(!CarrierDetector.looksLikeTrackingNumber("See you at 5"))
        #expect(!CarrierDetector.looksLikeTrackingNumber("https://example.com/abc"))
    }
}

struct PackageListTests {
    @Test func addsOnceSortsAndKeepsDelivered() {
        var list = PackageList()
        let first = list.add(TrackedPackage(number: "1Z999AA10123456784", nickname: "Shoes"))
        let again = list.add(TrackedPackage(number: "1z 999aa1 0123456784"))
        #expect(first && !again)
        #expect(list.packages.first?.carrier == .ups)
        list.add(TrackedPackage(number: "9400111899223197428490", expectedOn: DayKey(rawValue: "2026-10-09")))
        #expect(list.inTransit.first?.carrier == .usps)  // the one with a date leads
        list.packages[0].deliveredAt = Date()
        #expect(list.inTransit.count == 1 && list.delivered.count == 1)
    }

    @Test func expectedText() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let today = DayKey(rawValue: "2026-10-08")
        #expect(TrackedPackage(number: "1Z999AA10123456784", expectedOn: today).expectedText(today: today, calendar: cal) == "Arrives today")
        #expect(TrackedPackage(number: "1Z999AA10123456784", expectedOn: DayKey(rawValue: "2026-10-09")).expectedText(today: today, calendar: cal) == "Arrives tomorrow")
        #expect(TrackedPackage(number: "1Z999AA10123456784", expectedOn: DayKey(rawValue: "2026-10-05")).expectedText(today: today, calendar: cal)?.hasSuffix("(late)") == true)
    }

    @Test func mergeKeepsTheLaterChange() {
        var a = TrackedPackage(id: "p", number: "1Z999AA10123456784", addedAt: Date(timeIntervalSince1970: 0))
        var b = a
        b.deliveredAt = Date(timeIntervalSince1970: 100); b.updatedAt = Date(timeIntervalSince1970: 100)
        a.nickname = "old"
        let merged = PackageList.merge(local: PackageList(packages: [a]), remote: PackageList(packages: [b, TrackedPackage(number: "TBA123456789000")]))
        #expect(merged.packages.count == 2)
        #expect(merged.packages.first { $0.id == "p" }?.deliveredAt != nil)
    }
}

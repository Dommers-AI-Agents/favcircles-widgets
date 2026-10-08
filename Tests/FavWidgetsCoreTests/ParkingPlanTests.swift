import Testing
import Foundation
@testable import FavWidgetsCore

struct ParkingPlanTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parkedAndMeterText() {
        #expect(ParkingPlan.parkedText(now.addingTimeInterval(-20), now: now) == "Parked just now")
        #expect(ParkingPlan.parkedText(now.addingTimeInterval(-42 * 60), now: now) == "Parked 42 min ago")
        #expect(ParkingPlan.parkedText(now.addingTimeInterval(-125 * 60), now: now) == "Parked 2h 5m ago")
        #expect(ParkingPlan.meterText(nil, now: now) == nil)
        #expect(ParkingPlan.meterText(now.addingTimeInterval(17 * 60 + 10), now: now) == "18 min left")
        #expect(ParkingPlan.meterText(now.addingTimeInterval(90 * 60), now: now) == "1h 30m left")
        #expect(ParkingPlan.meterText(now.addingTimeInterval(-5 * 60), now: now) == "Meter expired 5 min ago")
    }

    @Test func remindersWarnThenExpire() {
        let hour = ParkingPlan.reminderTimes(meterEndsAt: now.addingTimeInterval(3600), now: now)
        #expect(hour.map(\.id) == ["parking-warn", "parking-expired"])
        #expect(hour[0].at == now.addingTimeInterval(3000))
        let short = ParkingPlan.reminderTimes(meterEndsAt: now.addingTimeInterval(8 * 60), now: now)
        #expect(short[0].at == now.addingTimeInterval(4 * 60))
        #expect(ParkingPlan.reminderTimes(meterEndsAt: now.addingTimeInterval(-60), now: now).isEmpty)
    }

    @Test func distances() {
        let d = ParkingPlan.distance((35.2271, -80.8431), (35.2271, -80.8331))
        #expect(abs(d - 908) < 10)
        #expect(ParkingPlan.distanceText(meters: 120, usesMetric: false) == "394 ft")
        #expect(ParkingPlan.distanceText(meters: 908, usesMetric: false) == "0.6 mi")
        #expect(ParkingPlan.distanceText(meters: 908, usesMetric: true) == "908 m")
        #expect(ParkingPlan.walkURL(ParkingSpot(latitude: 1, longitude: 2, savedAt: now))?.absoluteString.contains("dirflg=w") == true)
    }
}

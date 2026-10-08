import Foundation

/// Parking Spot (Wes, 2026-10-08): where you parked, a note, a meter timer.
/// One small document; the photo stays on the phone.
public struct ParkingState: WidgetModel {
    public static let schemaVersion = 1
    public var spot: ParkingSpot?
    public init(spot: ParkingSpot? = nil) { self.spot = spot }
    public static let empty = ParkingState()
}

public struct ParkingSpot: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var savedAt: Date
    public var note: String
    public var address: String?
    public var meterEndsAt: Date?
    public var hasPhoto: Bool
    public init(latitude: Double, longitude: Double, savedAt: Date, note: String = "", address: String? = nil,
                meterEndsAt: Date? = nil, hasPhoto: Bool = false) {
        self.latitude = latitude; self.longitude = longitude; self.savedAt = savedAt; self.note = note
        self.address = address; self.meterEndsAt = meterEndsAt; self.hasPhoto = hasPhoto
    }
}

public enum ParkingPlan {
    /// "Just now" / "Parked 42 min ago" / "Parked 2h 5m ago"
    public static func parkedText(_ savedAt: Date, now: Date) -> String {
        let m = max(0, Int(now.timeIntervalSince(savedAt) / 60))
        if m < 1 { return "Parked just now" }
        if m < 60 { return "Parked \(m) min ago" }
        if m < 24 * 60 { return "Parked \(m / 60)h \(m % 60)m ago" }
        return "Parked \(m / (24 * 60))d ago"
    }

    /// "18 min left" / "Meter expired 5 min ago"; nil without a meter
    public static func meterText(_ endsAt: Date?, now: Date) -> String? {
        guard let endsAt else { return nil }
        let s = Int(endsAt.timeIntervalSince(now))
        if s <= 0 {
            let m = -s / 60
            return m < 1 ? "Meter just expired" : "Meter expired \(m) min ago"
        }
        let m = Int((Double(s) / 60).rounded(.up))
        return m < 60 ? "\(m) min left" : "\(m / 60)h \(m % 60)m left"
    }

    /// The warning 10 min before (or half way, for short meters), and expiry.
    public static func reminderTimes(meterEndsAt: Date, now: Date) -> [(id: String, at: Date, text: String)] {
        let total = meterEndsAt.timeIntervalSince(now)
        guard total > 0 else { return [] }
        let lead = min(10 * 60, total / 2)
        var out: [(String, Date, String)] = []
        if lead >= 60 { out.append(("parking-warn", meterEndsAt.addingTimeInterval(-lead), "\(Int(lead / 60)) min left on your meter")) }
        out.append(("parking-expired", meterEndsAt, "Your parking meter just ran out"))
        return out
    }

    /// "0.3 mi" / "450 ft" (US) or "0.5 km" / "450 m"
    public static func distanceText(meters: Double, usesMetric: Bool) -> String {
        if usesMetric { return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000) }
        let feet = meters * 3.28084
        return feet < 1000 ? "\(Int(feet.rounded())) ft" : String(format: "%.1f mi", meters / 1609.344)
    }

    /// Meters between two coordinates (haversine).
    public static func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6_371_000.0
        let dLat = (b.0 - a.0) * .pi / 180, dLon = (b.1 - a.1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.0 * .pi / 180) * cos(b.0 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Apple Maps walking directions to the car.
    public static func walkURL(_ spot: ParkingSpot) -> URL? {
        URL(string: "http://maps.apple.com/?daddr=\(spot.latitude),\(spot.longitude)&dirflg=w")
    }
}

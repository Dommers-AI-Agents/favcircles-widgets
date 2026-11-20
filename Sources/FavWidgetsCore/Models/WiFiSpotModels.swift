import Foundation

/// Wi-Fi Here (Wes, 2026-11-20): the network and password for the places you
/// go back to — Dad's house, the cabin, your favorite café. When you are
/// there, the card shows it; a QR lets a guest join in one scan. One
/// document on the account, so a new phone has them (settings survive
/// reinstall); spots are never pruned.
public struct WiFiSpotList: WidgetModel {
    public static let schemaVersion = 1
    public var spots: [WiFiSpot]
    public init(spots: [WiFiSpot] = []) { self.spots = spots }
    public static let empty = WiFiSpotList()

    /// Two phones: union by id; the same spot keeps the later edit.
    public static func merge(local: WiFiSpotList, remote: WiFiSpotList) -> WiFiSpotList {
        var byId = Dictionary(remote.spots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in local.spots where (byId[s.id]?.updatedAt ?? .distantPast) <= s.updatedAt { byId[s.id] = s }
        return WiFiSpotList(spots: byId.values.sorted { $0.createdAt < $1.createdAt })
    }
}

public struct WiFiSpot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// "Dad's house", "Fresh Monkee"
    public var placeName: String
    /// The app's place id when it came from a saved place.
    public var placeId: String?
    public var coordinate: WidgetCoordinate?
    public var network: String
    public var password: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?

    public init(id: String = UUID().uuidString, placeName: String, placeId: String? = nil, coordinate: WidgetCoordinate? = nil,
                network: String, password: String, note: String = "", createdAt: Date = Date()) {
        self.id = id; self.placeName = placeName; self.placeId = placeId; self.coordinate = coordinate
        self.network = network; self.password = password; self.note = note
        self.createdAt = createdAt; self.updatedAt = createdAt
    }

    public var isOpenNetwork: Bool { password.isEmpty }
}

public enum WiFiPlan {
    /// How close "here" is: a house lot or a café and its patio.
    public static let hereRadiusMeters: Double = 150

    /// The saved spot you are standing at, nearest first; nil when none is
    /// within range or the location is unknown.
    public static func here(_ spots: [WiFiSpot], at location: WidgetCoordinate?, radius: Double = hereRadiusMeters) -> WiFiSpot? {
        guard let location else { return nil }
        return spots
            .compactMap { s in s.coordinate.map { (s, $0.distance(to: location)) } }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    /// The list order: the one you are at, then nearest, then most recently
    /// used, then newest.
    public static func sorted(_ spots: [WiFiSpot], near location: WidgetCoordinate?) -> [WiFiSpot] {
        spots.sorted { a, b in
            let da = location.flatMap { l in a.coordinate?.distance(to: l) } ?? .infinity
            let db = location.flatMap { l in b.coordinate?.distance(to: l) } ?? .infinity
            if da != db { return da < db }
            let ua = a.lastUsedAt ?? .distantPast, ub = b.lastUsedAt ?? .distantPast
            if ua != ub { return ua > ub }
            return a.createdAt > b.createdAt
        }
    }

    /// The standard Wi-Fi QR payload the iPhone camera understands:
    /// `WIFI:T:WPA;S:<network>;P:<password>;;` (open networks: `T:nopass`).
    /// Backslash, semicolon, comma, colon and quote are escaped.
    public static func qrPayload(network: String, password: String) -> String {
        func esc(_ s: String) -> String {
            var out = ""
            for ch in s {
                if ["\\", ";", ",", ":", "\""].contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        }
        if password.isEmpty { return "WIFI:T:nopass;S:\(esc(network));;" }
        return "WIFI:T:WPA;S:\(esc(network));P:\(esc(password));;"
    }

    /// "Guest · ••••••••" for the list; the password itself is shown on tap.
    public static func masked(_ password: String) -> String {
        password.isEmpty ? "Open network" : String(repeating: "•", count: min(12, max(6, password.count)))
    }

    /// The nearest saved place to stand in for "where I am" when adding a
    /// spot; nil when nothing is within `radius`.
    public static func nearestPlace(_ places: [WidgetPlaceCandidate], to location: WidgetCoordinate?,
                                    radius: Double = 250) -> WidgetPlaceCandidate? {
        guard let location else { return nil }
        return places.filter { $0.coordinate.distance(to: location) <= radius }
            .min { $0.coordinate.distance(to: location) < $1.coordinate.distance(to: location) }
    }
}

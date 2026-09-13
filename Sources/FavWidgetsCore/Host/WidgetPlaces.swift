import Foundation

/// A GPS coordinate; kept dependency-free (no CoreLocation) so the core
/// compiles anywhere.
public struct WidgetCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: WidgetCoordinate) -> Double {
        let r = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Whose list a place came from.
public enum WidgetPlaceSource: String, Codable, Hashable, Sendable, CaseIterable {
    case mine, connection, following

    public var label: String {
        switch self {
        case .mine: return "My places"
        case .connection: return "Connections"
        case .following: return "Following"
        }
    }
}

/// A place the app knows about, trimmed to what a widget needs.
public struct WidgetPlaceCandidate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let address: String?
    public let coordinate: WidgetCoordinate
    public let category: String
    public let source: WidgetPlaceSource
    /// Who saved it (a connection's or followed person's name); nil for mine.
    public let savedByName: String?
    /// Everyone who saved this venue, "You" first when the user did.
    public let savers: [String]
    public let photoURL: URL?
    /// True when `id` is a canonical globalPlaces id.
    public let isGlobal: Bool

    public init(id: String, name: String, address: String? = nil, coordinate: WidgetCoordinate, category: String,
                source: WidgetPlaceSource, savedByName: String? = nil, savers: [String] = [], photoURL: URL? = nil, isGlobal: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.category = category
        self.source = source
        self.savedByName = savedByName
        self.savers = savers.isEmpty ? (savedByName.map { [$0] } ?? []) : savers
        self.photoURL = photoURL
        self.isGlobal = isGlobal
    }

    public var placeRef: WidgetPlaceRef {
        WidgetPlaceRef(id: id, name: name, city: nil, isGlobal: isGlobal)
    }
}

/// What to fetch. Categories use the app's place category raw values
/// ("bar", "restaurant", …); empty means every category.
public struct WidgetPlaceQuery: Hashable, Sendable {
    public var categories: Set<String>
    public var sources: Set<WidgetPlaceSource>
    public var near: WidgetCoordinate?
    public var radiusMeters: Double

    public init(categories: Set<String> = [], sources: Set<WidgetPlaceSource> = Set(WidgetPlaceSource.allCases),
                near: WidgetCoordinate? = nil, radiusMeters: Double = 50_000) {
        self.categories = categories
        self.sources = sources
        self.near = near
        self.radiusMeters = radiusMeters
    }
}

import Foundation

/// What to Eat: spin a cuisine and a dish, then find saved restaurants
/// that serve it.
/// A restaurant from a map search (Apple Maps), not necessarily saved.
public struct NearbySpot: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let address: String?
    public let coordinate: WidgetCoordinate
    public let phone: String?
    public let url: URL?

    public init(name: String, address: String?, coordinate: WidgetCoordinate, phone: String? = nil, url: URL? = nil) {
        self.id = "\(name.lowercased())|\(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))"
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.phone = phone
        self.url = url
    }
}

public enum CravingPicker {
    public struct Spin: Equatable, Sendable {
        public let cuisine: Cuisine
        public let dish: Dish
        public var key: String { "\(cuisine.id)|\(dish.name)" }
    }

    public struct PlaceMatch: Equatable, Sendable {
        public let scored: NextBarPicker.Scored
        /// True when the name suggests this cuisine.
        public let matchesCuisine: Bool
    }

    public static let recentLimit = 8

    /// Every (cuisine, dish) that fits the filters: all filters when that
    /// leaves anything, else any one of them, else everything.
    public static func candidates(filters: Set<CravingTag>, cuisineId: String? = nil,
                                  in library: [Cuisine] = CravingLibrary.all) -> [Spin] {
        let cuisines = library.filter { cuisineId == nil || $0.id == cuisineId }
        let everything = cuisines.flatMap { c in c.dishes.map { Spin(cuisine: c, dish: $0) } }
        guard !filters.isEmpty else { return everything }
        let all = everything.filter { filters.isSubset(of: $0.dish.tags) }
        if !all.isEmpty { return all }
        let any = everything.filter { !$0.dish.tags.isDisjoint(with: filters) }
        return any.isEmpty ? everything : any
    }

    /// A random spin, avoiding recent keys when anything else fits. The
    /// cuisine is chosen first so a cuisine with many dishes isn't favored.
    public static func spin(filters: Set<CravingTag> = [], cuisineId: String? = nil, excluding: [String] = [],
                            in library: [Cuisine] = CravingLibrary.all,
                            random: () -> Double = { Double.random(in: 0..<1) }) -> Spin? {
        let pool = candidates(filters: filters, cuisineId: cuisineId, in: library)
        let fresh = pool.filter { !excluding.contains($0.key) }
        let choices = fresh.isEmpty ? pool : fresh
        let cuisineIds = Array(Set(choices.map(\.cuisine.id))).sorted()
        guard !cuisineIds.isEmpty else { return nil }
        let cuisineId = cuisineIds[min(cuisineIds.count - 1, Int(random() * Double(cuisineIds.count)))]
        let dishes = choices.filter { $0.cuisine.id == cuisineId }
        return dishes[min(dishes.count - 1, Int(random() * Double(dishes.count)))]
    }

    /// True when a restaurant's name contains one of the cuisine's words
    /// as whole words ("Pho Real" is Vietnamese; "Phoenix Grill" is not).
    public static func nameSuggests(_ cuisine: Cuisine, name: String) -> Bool {
        let padded = " " + words(name) + " "
        return cuisine.keywords.contains { padded.contains(" " + words($0) + " ") }
    }

    /// Same venue: within 75 m and sharing a meaningful name word ("Sushi
    /// Hana" vs "Hana Sushi Bar"), so a map result can vouch for a save.
    public static func sameVenue(_ name: String, _ a: WidgetCoordinate, _ other: String, _ b: WidgetCoordinate) -> Bool {
        guard a.distance(to: b) <= 75 else { return false }
        let stop: Set<String> = ["the", "and", "of", "restaurant", "bar", "grill", "kitchen", "cafe", "co", "company", "at", "on"]
        let wa = Set(words(name).split(separator: " ").map(String.init).filter { $0.count > 1 && !stop.contains($0) })
        let wb = Set(words(other).split(separator: " ").map(String.init).filter { $0.count > 1 && !stop.contains($0) })
        return !wa.isDisjoint(with: wb)
    }

    /// The answer to "where can I get it?": saved places that serve it (by
    /// name, or because the map search lists them for this cuisine), and map
    /// results nobody has saved, nearest first. Nothing invented: if neither
    /// has anything, both lists are empty.
    public struct Where: Equatable, Sendable {
        public let saved: [PlaceMatch]          // serves the cuisine
        public let nearby: [NearbySpot]         // map results, not already saved
        public let otherSaved: [PlaceMatch]     // the rest of your saves, for when you just want somewhere
    }

    public static func whereToGet(_ cuisine: Cuisine?, candidates: [WidgetPlaceCandidate], spots: [NearbySpot],
                                  origin: WidgetCoordinate?, maxDistanceMeters: Double,
                                  sources: Set<WidgetPlaceSource>) -> Where {
        let pool = NextBarPicker.pool(candidates, origin: origin, maxDistanceMeters: maxDistanceMeters, sources: sources)
        var saved: [PlaceMatch] = []
        var other: [PlaceMatch] = []
        var vouched = Set<String>()
        for item in pool {
            let c = item.candidate
            let byName = cuisine.map { nameSuggests($0, name: c.name) } ?? false
            let spot = spots.first { sameVenue(c.name, c.coordinate, $0.name, $0.coordinate) }
            if let spot { vouched.insert(spot.id) }
            if byName || spot != nil {
                saved.append(PlaceMatch(scored: item, matchesCuisine: true))
            } else {
                other.append(PlaceMatch(scored: item, matchesCuisine: false))
            }
        }
        let inRange = spots.filter { origin == nil || origin!.distance(to: $0.coordinate) <= maxDistanceMeters }
        let nearby = inRange.filter { !vouched.contains($0.id) }
            .sorted { (origin?.distance(to: $0.coordinate) ?? 0) < (origin?.distance(to: $1.coordinate) ?? 0) }
        return Where(saved: saved, nearby: nearby, otherSaved: other)
    }

    /// Saved restaurants in range: ones whose names suggest the cuisine
    /// first (nearest first), then everything else nearest first.
    public static func places(for cuisine: Cuisine?, candidates: [WidgetPlaceCandidate], origin: WidgetCoordinate?,
                              maxDistanceMeters: Double, sources: Set<WidgetPlaceSource>) -> [PlaceMatch] {
        let pool = NextBarPicker.pool(candidates, origin: origin, maxDistanceMeters: maxDistanceMeters, sources: sources)
        let matches = pool.map { item in
            PlaceMatch(scored: item, matchesCuisine: cuisine.map { nameSuggests($0, name: item.candidate.name) } ?? false)
        }
        return matches.filter(\.matchesCuisine) + matches.filter { !$0.matchesCuisine }
    }

    static func words(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Single document (`whattoeat`): filters, the current spin, a no-repeat
/// ring, and the place picked for it.
public struct WhatToEatSettings: WidgetModel {
    public var filters: Set<CravingTag>
    /// "Type of food": nil = any cuisine.
    public var cuisineFilter: String?
    public var currentCuisineId: String?
    public var currentDish: String?
    public var recentKeys: [String]
    public var maxDistanceMeters: Double
    public var sources: Set<WidgetPlaceSource>

    public init(filters: Set<CravingTag> = [], cuisineFilter: String? = nil, currentCuisineId: String? = nil, currentDish: String? = nil,
                recentKeys: [String] = [], maxDistanceMeters: Double = 10_000,
                sources: Set<WidgetPlaceSource> = Set(WidgetPlaceSource.allCases)) {
        self.filters = filters
        self.cuisineFilter = cuisineFilter
        self.currentCuisineId = currentCuisineId
        self.currentDish = currentDish
        self.recentKeys = recentKeys
        self.maxDistanceMeters = maxDistanceMeters
        self.sources = sources
    }

    public static let empty = WhatToEatSettings()

    public var currentCuisine: Cuisine? { currentCuisineId.flatMap(CravingLibrary.cuisine(id:)) }

    public mutating func noteSpin(_ spin: CravingPicker.Spin) {
        currentCuisineId = spin.cuisine.id
        currentDish = spin.dish.name
        recentKeys.removeAll { $0 == spin.key }
        recentKeys.append(spin.key)
        if recentKeys.count > CravingPicker.recentLimit { recentKeys.removeFirst(recentKeys.count - CravingPicker.recentLimit) }
    }

    // Tolerant decoding: unknown tags or sources are dropped, not fatal.
    enum CodingKeys: String, CodingKey { case filters, cuisineFilter, currentCuisineId, currentDish, recentKeys, maxDistanceMeters, sources }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filters = Set(((try? c.decodeIfPresent([String].self, forKey: .filters)) ?? nil ?? []).compactMap(CravingTag.init(rawValue:)))
        // A cuisine this build doesn't know means "any"
        cuisineFilter = (try c.decodeIfPresent(String.self, forKey: .cuisineFilter)).flatMap { CravingLibrary.cuisine(id: $0) == nil ? nil : $0 }
        currentCuisineId = try c.decodeIfPresent(String.self, forKey: .currentCuisineId)
        currentDish = try c.decodeIfPresent(String.self, forKey: .currentDish)
        recentKeys = try c.decodeIfPresent([String].self, forKey: .recentKeys) ?? []
        maxDistanceMeters = try c.decodeIfPresent(Double.self, forKey: .maxDistanceMeters) ?? 10_000
        let rawSources = (try? c.decodeIfPresent([String].self, forKey: .sources)) ?? nil
        let decoded = Set((rawSources ?? []).compactMap(WidgetPlaceSource.init(rawValue:)))
        sources = decoded.isEmpty ? Set(WidgetPlaceSource.allCases) : decoded
    }
}

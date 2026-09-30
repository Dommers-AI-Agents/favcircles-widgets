import Foundation

/// What to Eat: spin a cuisine and a dish, then find saved restaurants
/// that serve it.
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
    public static func spin(filters: Set<CravingTag> = [], excluding: [String] = [],
                            in library: [Cuisine] = CravingLibrary.all,
                            random: () -> Double = { Double.random(in: 0..<1) }) -> Spin? {
        let pool = candidates(filters: filters, in: library)
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
    public var currentCuisineId: String?
    public var currentDish: String?
    public var recentKeys: [String]
    public var maxDistanceMeters: Double
    public var sources: Set<WidgetPlaceSource>

    public init(filters: Set<CravingTag> = [], currentCuisineId: String? = nil, currentDish: String? = nil,
                recentKeys: [String] = [], maxDistanceMeters: Double = 10_000,
                sources: Set<WidgetPlaceSource> = Set(WidgetPlaceSource.allCases)) {
        self.filters = filters
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
    enum CodingKeys: String, CodingKey { case filters, currentCuisineId, currentDish, recentKeys, maxDistanceMeters, sources }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filters = Set(((try? c.decodeIfPresent([String].self, forKey: .filters)) ?? nil ?? []).compactMap(CravingTag.init(rawValue:)))
        currentCuisineId = try c.decodeIfPresent(String.self, forKey: .currentCuisineId)
        currentDish = try c.decodeIfPresent(String.self, forKey: .currentDish)
        recentKeys = try c.decodeIfPresent([String].self, forKey: .recentKeys) ?? []
        maxDistanceMeters = try c.decodeIfPresent(Double.self, forKey: .maxDistanceMeters) ?? 10_000
        let rawSources = (try? c.decodeIfPresent([String].self, forKey: .sources)) ?? nil
        let decoded = Set((rawSources ?? []).compactMap(WidgetPlaceSource.init(rawValue:)))
        sources = decoded.isEmpty ? Set(WidgetPlaceSource.allCases) : decoded
    }
}

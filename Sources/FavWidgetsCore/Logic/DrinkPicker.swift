import Foundation

/// Make Me a Drink: pure picking and searching over `CocktailLibrary`.
public enum DrinkPicker {
    /// How many recent picks a surprise avoids repeating.
    public static let recentLimit = 5

    /// Drinks matching the filters (nil = any).
    public static func filtered(base: SpiritBase? = nil, style: CocktailStyle? = nil,
                                in library: [Cocktail] = CocktailLibrary.all) -> [Cocktail] {
        library.filter { (base == nil || $0.base == base) && (style == nil || $0.style == style) }
    }

    /// One random drink for the filters, avoiding `excluding` when anything
    /// else qualifies. `random` is injectable for tests (0 ..< 1).
    public static func random(base: SpiritBase? = nil, style: CocktailStyle? = nil, excluding: [String] = [],
                              in library: [Cocktail] = CocktailLibrary.all,
                              random: () -> Double = { Double.random(in: 0..<1) }) -> Cocktail? {
        let pool = filtered(base: base, style: style, in: library)
        let fresh = pool.filter { !excluding.contains($0.id) }
        let choices = fresh.isEmpty ? pool : fresh
        guard !choices.isEmpty else { return nil }
        let index = min(choices.count - 1, Int(random() * Double(choices.count)))
        return choices[index]
    }

    /// Case- and accent-insensitive lookup by name or alias, then by style
    /// ("sour", "tiki") or base ("gin"). Exact and prefix matches first.
    public static func search(_ query: String, in library: [Cocktail] = CocktailLibrary.all) -> [Cocktail] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        var ranked: [(rank: Int, drink: Cocktail)] = []
        for drink in library {
            let names = ([drink.name] + drink.aliases).map(normalize)
            let rank: Int?
            if names.contains(q) {
                rank = 0
            } else if names.contains(where: { $0.hasPrefix(q) }) {
                rank = 1
            } else if names.contains(where: { $0.contains(q) }) {
                rank = 2
            } else if normalize(drink.style.label) == q || normalize(drink.style.rawValue) == q
                        || normalize(drink.base.label) == q || normalize(drink.base.rawValue) == q
                        || q.hasSuffix("s") && normalize(drink.style.label) == String(q.dropLast()) {
                rank = 3
            } else if drink.ingredients.contains(where: { normalize($0.item).contains(q) }) {
                rank = 4
            } else {
                rank = nil
            }
            if let rank { ranked.append((rank, drink)) }
        }
        return ranked.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.drink.name < $1.drink.name }.map(\.drink)
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Single document (`drink`): the current pick, a short no-repeat ring,
/// the chosen base filter and favorites.
public struct DrinkSettings: WidgetModel {
    public var currentPickId: String?
    public var recentIds: [String]
    public var baseFilter: SpiritBase?
    public var favoriteIds: [String]

    public init(currentPickId: String? = nil, recentIds: [String] = [], baseFilter: SpiritBase? = nil, favoriteIds: [String] = []) {
        self.currentPickId = currentPickId
        self.recentIds = recentIds
        self.baseFilter = baseFilter
        self.favoriteIds = favoriteIds
    }

    public static let empty = DrinkSettings()

    public var currentPick: Cocktail? { currentPickId.flatMap(CocktailLibrary.cocktail(id:)) }

    public mutating func notePick(_ drink: Cocktail) {
        currentPickId = drink.id
        recentIds.removeAll { $0 == drink.id }
        recentIds.append(drink.id)
        if recentIds.count > DrinkPicker.recentLimit { recentIds.removeFirst(recentIds.count - DrinkPicker.recentLimit) }
    }

    public mutating func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) { favoriteIds.removeAll { $0 == id } } else { favoriteIds.append(id) }
    }

    /// Favorites are additive across devices.
    public static func merge(local: DrinkSettings, remote: DrinkSettings) -> DrinkSettings {
        var merged = local
        for id in remote.favoriteIds where !merged.favoriteIds.contains(id) { merged.favoriteIds.append(id) }
        return merged
    }

    // Tolerant decoding: a base this build doesn't know becomes "any".
    enum CodingKeys: String, CodingKey { case currentPickId, recentIds, baseFilter, favoriteIds }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentPickId = try c.decodeIfPresent(String.self, forKey: .currentPickId)
        recentIds = try c.decodeIfPresent([String].self, forKey: .recentIds) ?? []
        baseFilter = (try? c.decodeIfPresent(String.self, forKey: .baseFilter)).flatMap { $0.flatMap(SpiritBase.init(rawValue:)) }
        favoriteIds = try c.decodeIfPresent([String].self, forKey: .favoriteIds) ?? []
    }
}

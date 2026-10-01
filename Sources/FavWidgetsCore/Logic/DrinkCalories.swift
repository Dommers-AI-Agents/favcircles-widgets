import Foundation

/// About how many calories one drink has, worked out from its recipe.
///
/// An estimate, shown as "≈ 180 cal": each ingredient is matched to a
/// calories-per-ounce figure (80-proof spirits ≈ 64, liqueurs ≈ 90–100,
/// simple syrup ≈ 50, citrus ≈ 7, cream ≈ 100…) and multiplied by its
/// measure. Batch recipes (a bottle of sangria, a pitcher of horchata) are
/// scaled to one 6 oz serving. Rounded to the nearest 10.
public enum DrinkCalories {
    /// What one ingredient line is worth.
    struct Rate {
        /// Calories per US fluid ounce (or per item, when `perItem`).
        let calories: Double
        /// Counted, not measured: "1 egg white", "2 sugar cubes".
        var perItem = false
    }

    /// Calories for one drink, rounded to the nearest 10; nil when any
    /// measured ingredient is unknown (better no number than a wrong one).
    public static func estimate(_ drink: Cocktail) -> Int? {
        var total = 0.0
        var volume = 0.0
        for ingredient in drink.ingredients {
            guard let rate = rate(for: ingredient.item) else { return nil }
            let quantity = amount(ingredient.amount, item: ingredient.item)
            if rate.perItem {
                total += quantity.count * rate.calories
            } else {
                total += quantity.ounces * rate.calories
                volume += quantity.ounces
            }
        }
        // A batch: the recipe makes several drinks
        if volume > batchThreshold { total *= servingOunces / volume }
        return Int((total / 10).rounded()) * 10
    }

    /// "≈ 180 cal", or nil when it can't be estimated.
    public static func label(_ drink: Cocktail) -> String? {
        estimate(drink).map { "≈ \($0) cal" }
    }

    static let batchThreshold = 16.0
    static let servingOunces = 6.0
    /// An empty-measure topper ("ginger beer to top"): about a glass's worth.
    static let toppedOunces = 3.0

    // MARK: - Amounts

    struct Quantity { var ounces = 0.0; var count = 0.0 }

    static func amount(_ raw: String, item: String) -> Quantity {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.isEmpty {
            // "ginger beer to top" adds up; "salt to taste" doesn't
            return item.lowercased().contains("to top") ? Quantity(ounces: toppedOunces, count: 1) : Quantity()
        }
        let number = leadingNumber(text)
        let unitOunces: Double
        if text.contains("dash") { unitOunces = 1.0 / 32 }
        else if text.contains("drop") { unitOunces = 1.0 / 600 }
        else if text.contains("tbsp") { unitOunces = 0.5 }
        else if text.contains("tsp") { unitOunces = 1.0 / 6 }
        else if text.contains("cup") { unitOunces = 8 }
        else if text.contains("bottle") { unitOunces = 25.4 }
        else { unitOunces = 1 }
        return Quantity(ounces: number * unitOunces, count: number)
    }

    /// "1½" → 1.5, "¾" → 0.75, "2–3" → 2.5, "12" → 12.
    static func leadingNumber(_ text: String) -> Double {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
        func parse(_ part: Substring) -> Double? {
            var whole = ""
            var fraction = 0.0
            for char in part {
                if char.isNumber, let _ = Int(String(char)) { whole.append(char) }
                else if let f = fractions[char] { fraction = f; break }
                else if char == "." { whole.append(char) }
                else { break }
            }
            let value = (Double(whole) ?? 0) + fraction
            return value > 0 ? value : nil
        }
        let parts = text.split(whereSeparator: { $0 == "–" || $0 == "-" }).map { $0.trimmingCharacters(in: .whitespaces) }
        let values = parts.compactMap { parse(Substring($0)) }
        guard !values.isEmpty else { return 1 }
        return values.prefix(2).reduce(0, +) / Double(min(values.count, 2))
    }

    // MARK: - Ingredients

    /// First match wins: specific before general ("sloe gin" before "gin").
    /// Single words match whole words only, so "ginger beer" is never gin.
    static let table: [(keys: [String], rate: Rate)] = [
        // Before "water", "beer" and "sugar cube" below
        (["tonic"], Rate(calories: 10)),
        (["ginger beer"], Rate(calories: 12)),
        (["simple syrup"], Rate(calories: 50)),
        // Nothing worth counting
        (["bitters", "salt", "pepper", "hot sauce", "worcestershire", "mint", "basil", "leaves", "cloves", "star anise",
          "cinnamon stick", "cinnamon sticks", "cardamom", "jalapeño", "orange flower water", "vanilla extract",
          "squeeze of lime", "absinthe to rinse", "cucumber", "rice"], Rate(calories: 0)),
        (["club soda", "seltzer", "sparkling water", "topo chico", "soda water", "hot water", "cold water", "water"], Rate(calories: 0)),
        // Counted garnishes and extras
        (["egg white"], Rate(calories: 17, perItem: true)),
        (["sugar cube"], Rate(calories: 16, perItem: true)),
        (["maraschino cherry"], Rate(calories: 8, perItem: true)),
        (["orange slice", "orange slices", "orange, sliced"], Rate(calories: 5, perItem: true)),
        (["wedges", "lemon wedges"], Rate(calories: 2, perItem: true)),
        // Stronger than usual first
        (["151-proof"], Rate(calories: 120)),
        (["cask-strength"], Rate(calories: 85)),
        (["sloe gin", "apricot brandy", "southern comfort"], Rate(calories: 80)),
        // Liqueurs, amari and aperitivi
        (["aperol"], Rate(calories: 45)),
        (["pimm's"], Rate(calories: 50)),
        (["campari"], Rate(calories: 70)),
        (["fernet", "amaro", "jägermeister"], Rate(calories: 80)),
        (["irish cream"], Rate(calories: 95)),
        (["coffee liqueur", "liqueur", "curaçao", "cointreau", "triple sec", "grand marnier", "chartreuse", "bénédictine",
          "drambuie", "galliano", "crème de", "schnapps", "amaretto", "midori", "limoncello", "st-germain", "chambord",
          "absinthe", "pernod"], Rate(calories: 95)),
        // Fortified and aromatized wines
        (["sweet vermouth"], Rate(calories: 45)),
        (["dry vermouth"], Rate(calories: 32)),
        (["blanc vermouth", "lillet"], Rate(calories: 40)),
        (["port"], Rate(calories: 47)),
        (["sherry"], Rate(calories: 36)),
        // Spirits (80 proof)
        (["vodka", "gin", "rum", "tequila", "mezcal", "whiskey", "whisky", "bourbon", "rye", "scotch", "brandy", "cognac",
          "pisco", "applejack", "calvados"], Rate(calories: 64)),
        // Wine and beer
        (["champagne", "prosecco", "sparkling wine", "cava"], Rate(calories: 23)),
        (["wine"], Rate(calories: 24)),
        (["stout", "lager", "beer"], Rate(calories: 13)),
        // Syrups and sweeteners
        (["batter (butter", "spiced butter batter"], Rate(calories: 120)),
        (["tom and jerry batter"], Rate(calories: 70)),
        (["sweetened condensed milk"], Rate(calories: 90)),
        (["honey syrup", "honey-ginger syrup"], Rate(calories: 64)),
        (["honey"], Rate(calories: 85)),
        (["demerara syrup", "rich simple syrup"], Rate(calories: 70)),
        (["grenadine"], Rate(calories: 75)),
        (["orgeat"], Rate(calories: 80)),
        (["chocolate syrup"], Rate(calories: 70)),
        (["agave"], Rate(calories: 60)),
        (["falernum", "brown sugar syrup"], Rate(calories: 60)),
        (["syrup"], Rate(calories: 50)),
        (["sugar"], Rate(calories: 96)),
        (["sour mix"], Rate(calories: 30)),
        (["don's mix"], Rate(calories: 20)),
        (["sangrita"], Rate(calories: 10)),
        // Dairy and coconut
        (["cream of coconut"], Rate(calories: 110)),
        (["half-and-half", "evaporated milk"], Rate(calories: 40)),
        (["heavy cream", "whipped cream"], Rate(calories: 100)),
        (["milk", "yogurt"], Rate(calories: 18)),
        // Fruit and juices
        (["mango pulp"], Rate(calories: 25)),
        (["purée"], Rate(calories: 15)),
        (["strawberries", "strawberry"], Rate(calories: 9)),
        (["watermelon"], Rate(calories: 4)),
        (["pineapple juice"], Rate(calories: 16)),
        (["passion fruit juice"], Rate(calories: 16)),
        (["cranberry juice"], Rate(calories: 15)),
        (["apple cider"], Rate(calories: 15)),
        (["orange juice"], Rate(calories: 14)),
        (["grapefruit juice"], Rate(calories: 12)),
        (["tomato juice"], Rate(calories: 5)),
        (["lime juice", "lemon juice", "lime, cut"], Rate(calories: 7)),
        // After the liqueurs, so "coffee liqueur" is never plain coffee
        (["espresso", "coffee", "iced tea", "thai tea", "brewed"], Rate(calories: 1)),
        // Sodas
        (["energy drink", "grapefruit soda"], Rate(calories: 13)),
        (["cola", "coca-cola", "lemon-lime soda", "lemon soda", "lemonade"], Rate(calories: 12)),
        (["ginger ale"], Rate(calories: 10)),
        (["splash of", "sliced oranges", "cucumber, strawberry"], Rate(calories: 0)),
    ]

    static func rate(for item: String) -> Rate? {
        let text = item.lowercased()
        let words = Set(text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init))
        for entry in table {
            for key in entry.keys {
                let isPhrase = key.contains(" ") || key.contains(",") || key.contains("(") || key.contains("-")
                let matches = isPhrase ? text.contains(key) : words.contains(key)
                if matches { return entry.rate }
            }
        }
        return nil
    }
}

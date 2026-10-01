import Testing
import Foundation
@testable import FavWidgetsCore

/// The calorie line on every drink card: estimated from the recipe.
struct DrinkCaloriesTests {
    private func cal(_ id: String) -> Int? { CocktailLibrary.cocktail(id: id).flatMap(DrinkCalories.estimate) }

    @Test func everyDrinkHasAnEstimate() {
        // A new ingredient no one priced shows no number rather than a wrong
        // one, so the library must stay fully covered
        let missing = CocktailLibrary.all.filter { DrinkCalories.estimate($0) == nil }.map(\.name)
        #expect(missing.isEmpty, "unpriced: \(missing)")
        let unknown = Set(CocktailLibrary.all.flatMap(\.ingredients).map(\.item).filter { DrinkCalories.rate(for: $0) == nil })
        #expect(unknown.isEmpty, "unknown ingredients: \(unknown.sorted())")
    }

    @Test func classicsLandWhereTheyShould() {
        // Published ballparks for standard pours
        #expect((90...130).contains(cal("vodka-soda") ?? 0))          // 1½ oz vodka + soda ≈ 100
        #expect((120...200).contains(cal("old-fashioned") ?? 0))      // 2 oz 80-proof whiskey + syrup ≈ 140
        #expect((180...280).contains(cal("margarita") ?? 0))          // ≈ 200–250
        #expect((300...500).contains(cal("pina-colada") ?? 0))        // creamy, ≈ 400
        #expect((150...260).contains(cal("gin-and-tonic") ?? 0))      // 2 oz gin + 4 oz tonic ≈ 170
        #expect((0...60).contains(cal("arnold-palmer") ?? -1))        // zero-proof, lemonade + tea
    }

    @Test func aBatchIsScaledToOneServing() {
        // Sangria starts from a whole bottle; one glass is a normal number
        #expect((80...250).contains(cal("sangria") ?? 0))
    }

    @Test func amountsParse() {
        #expect(DrinkCalories.leadingNumber("1½") == 1.5)
        #expect(DrinkCalories.leadingNumber("¾") == 0.75)
        #expect(DrinkCalories.leadingNumber("2–3") == 2.5)
        #expect(DrinkCalories.amount("2 tsp", item: "sugar").ounces == 2.0 / 6)
        #expect(DrinkCalories.amount("", item: "ginger beer to top").ounces == 3)
        #expect(DrinkCalories.amount("", item: "salt to taste").ounces == 0)
    }

    @Test func wordsMatchWholeWords() {
        #expect(DrinkCalories.rate(for: "ginger beer")?.calories == 12)   // not gin
        #expect(DrinkCalories.rate(for: "tonic water")?.calories == 10)   // not water
        #expect(DrinkCalories.rate(for: "Fernet-Branca")?.calories == 80)
        #expect(DrinkCalories.rate(for: "coffee liqueur")?.calories == 95)  // not coffee
        #expect(DrinkCalories.rate(for: "hot coffee")?.calories == 1)
        #expect((220...360).contains(cal("white-russian") ?? 0))          // vodka, coffee liqueur, cream
        #expect(DrinkCalories.label(CocktailLibrary.cocktail(id: "vodka-soda")!)?.hasPrefix("≈ ") == true)
    }
}

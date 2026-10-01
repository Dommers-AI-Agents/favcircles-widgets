import Testing
import Foundation
@testable import FavWidgetsCore

struct DrinkPickerTests {
    @Test func libraryIsCompleteAndUnique() {
        let all = CocktailLibrary.all
        #expect(all.count >= 200)
        #expect(Set(all.map(\.id)).count == all.count, "duplicate ids")
        let names = all.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count, "duplicate names")
        for drink in all {
            #expect(!drink.ingredients.isEmpty, "\(drink.name) has no ingredients")
            #expect(!drink.steps.isEmpty, "\(drink.name) has no steps")
            #expect(!drink.glass.isEmpty, "\(drink.name) has no glass")
            #expect(!drink.blurb.isEmpty && !drink.orderTip.isEmpty, "\(drink.name) is missing copy")
            #expect(drink.id == drink.id.lowercased() && !drink.id.contains(" "), "\(drink.id) isn't kebab-case")
        }
        // Wes, 2026-10-01: at least 20 per spirit chip, so a surprise rarely repeats
        for base in SpiritBase.allCases {
            #expect(DrinkPicker.filtered(base: base).count >= 20, "\(base.label) has only \(DrinkPicker.filtered(base: base).count)")
        }
    }

    @Test func zeroProofDrinksHaveNoAlcohol() {
        let alcohol = ["vodka", "gin", "rum", "tequila", "mezcal", "whiskey", "whisky", "bourbon", "rye", "scotch",
                       "brandy", "cognac", "wine", "champagne", "prosecco", "liqueur", "vermouth", "bitters",
                       "schnapps", "amaro", "campari", "aperol", "beer", "cider", "sake", "port", "sherry"]
        for drink in DrinkPicker.filtered(base: .zeroProof) {
            for ingredient in drink.ingredients {
                let words = Set(ingredient.item.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
                // "ginger beer", "root beer", "apple cider" and "non-alcoholic …" are fine
                let soft = ingredient.item.lowercased()
                if soft.contains("ginger beer") || soft.contains("root beer") || soft.contains("non-alcoholic")
                    || soft.contains("apple cider") || soft.contains("zero-proof") { continue }
                #expect(words.isDisjoint(with: alcohol), "\(drink.name): \(ingredient.item)")
            }
        }
    }

    @Test func findsTheManhattanHoweverItIsTyped() {
        #expect(DrinkPicker.search("manhattan").first?.id == "manhattan")
        #expect(DrinkPicker.search("Manhattan ").first?.id == "manhattan")
        #expect(DrinkPicker.search("MANHAT").first?.id == "manhattan")
        #expect(DrinkPicker.search("pina colada").first?.id == "pina-colada")
        #expect(DrinkPicker.search("Piña Colada").first?.id == "pina-colada")
        #expect(DrinkPicker.search("g&t").first?.id == "gin-and-tonic")
        #expect(DrinkPicker.search("  ").isEmpty)
    }

    @Test func styleAndBaseWordsFindThatKind() {
        let sours = DrinkPicker.search("sour")
        #expect(sours.contains { $0.id == "whiskey-sour" })
        #expect(DrinkPicker.search("sours").contains { $0.style == .sour })
        #expect(DrinkPicker.search("tiki").allSatisfy { $0.style == .tiki || $0.name.lowercased().contains("tiki") })
        #expect(DrinkPicker.search("tequila").contains { $0.id == "margarita" })
    }

    @Test func aBaseFilterOnlyReturnsThatBase() {
        for _ in 0..<50 {
            let drink = DrinkPicker.random(base: .tequila)
            #expect(drink?.base == .tequila)
        }
    }

    @Test func surprisesDoNotRepeatRecentPicks() {
        var settings = DrinkSettings.empty
        for _ in 0..<40 {
            let next = DrinkPicker.random(base: .gin, excluding: settings.recentIds)!
            #expect(!settings.recentIds.contains(next.id), "repeated \(next.id)")
            settings.notePick(next)
        }
        #expect(settings.recentIds.count == DrinkPicker.recentLimit)
    }

    @Test func favoritesMergeAcrossDevices() {
        var a = DrinkSettings.empty; a.toggleFavorite("negroni")
        var b = DrinkSettings.empty; b.toggleFavorite("mojito")
        #expect(Set(DrinkSettings.merge(local: a, remote: b).favoriteIds) == ["negroni", "mojito"])
        a.toggleFavorite("negroni")
        #expect(a.favoriteIds.isEmpty)
    }

    @Test func unknownBaseDecodesAsAny() throws {
        let json = #"{"currentPickId":"manhattan","recentIds":[],"baseFilter":"absinthe","favoriteIds":["martini"]}"#
        let s = try WidgetJSON.decode(DrinkSettings.self, from: Data(json.utf8))
        #expect(s.baseFilter == nil)
        #expect(s.currentPick?.name == "Manhattan")
    }
}

struct CravingPickerTests {
    private func place(_ name: String, metersNorth: Double) -> WidgetPlaceCandidate {
        WidgetPlaceCandidate(id: name, name: name, address: nil,
                             coordinate: WidgetCoordinate(latitude: 35.2271 + metersNorth / 111_320, longitude: -80.8431),
                             category: "restaurant", source: .mine, savedByName: nil, savers: ["You"], photoURL: nil, isGlobal: true)
    }
    private let origin = WidgetCoordinate(latitude: 35.2271, longitude: -80.8431)

    @Test func libraryIsComplete() {
        #expect(CravingLibrary.all.count >= 18)
        #expect(Set(CravingLibrary.all.map(\.id)).count == CravingLibrary.all.count)
        for c in CravingLibrary.all { #expect(c.dishes.count >= 5, "\(c.name) is thin") }
    }

    @Test func spinsHonorFilters() {
        for _ in 0..<60 {
            let spin = CravingPicker.spin(filters: [.spicy])!
            #expect(spin.dish.tags.contains(.spicy))
            let veg = CravingPicker.spin(filters: [.vegetarian])!
            #expect(veg.dish.tags.contains(.vegetarian))
        }
    }

    @Test func typeOfFoodPinsTheCuisine() {
        for _ in 0..<40 {
            let spin = CravingPicker.spin(filters: [], cuisineId: "thai")!
            #expect(spin.cuisine.id == "thai")
            let both = CravingPicker.spin(filters: [.spicy], cuisineId: "thai")!
            #expect(both.cuisine.id == "thai" && both.dish.tags.contains(.spicy))
        }
        // A mood the cuisine can't satisfy still answers from that cuisine
        #expect(CravingPicker.spin(filters: [.splurge], cuisineId: "vietnamese")?.cuisine.id == "vietnamese")
    }

    @Test func unknownCuisineFilterDecodesAsAny() throws {
        let json = #"{"filters":["spicy","nope"],"cuisineFilter":"martian","recentKeys":[],"maxDistanceMeters":5000,"sources":["mine"]}"#
        let s = try WidgetJSON.decode(WhatToEatSettings.self, from: Data(json.utf8))
        #expect(s.cuisineFilter == nil)
        #expect(s.filters == [.spicy])
        var t = WhatToEatSettings.empty; t.cuisineFilter = "thai"
        let round = try WidgetJSON.decode(WhatToEatSettings.self, from: JSONEncoder().encode(t))
        #expect(round.cuisineFilter == "thai")
    }

    @Test func impossibleFilterCombosStillGiveAnAnswer() {
        // Nothing is spicy + light + splurge + vegetarian; fall back to any of them
        #expect(CravingPicker.spin(filters: [.spicy, .splurge, .vegetarian, .light]) != nil)
    }

    @Test func spinsAvoidRecentOnes() {
        var settings = WhatToEatSettings.empty
        for _ in 0..<40 {
            let spin = CravingPicker.spin(filters: [.spicy], excluding: settings.recentKeys)!
            #expect(!settings.recentKeys.contains(spin.key))
            settings.noteSpin(spin)
        }
    }

    @Test func namesGiveTheCuisineAway() {
        let viet = CravingLibrary.cuisine(id: "vietnamese")!
        #expect(CravingPicker.nameSuggests(viet, name: "Pho Real"))
        #expect(!CravingPicker.nameSuggests(viet, name: "Phoenix Grill"))
        let mex = CravingLibrary.cuisine(id: "mexican")!
        #expect(CravingPicker.nameSuggests(mex, name: "Taqueria El Pastor"))
        #expect(!CravingPicker.nameSuggests(mex, name: "La Dolce Vita"))
        #expect(CravingPicker.nameSuggests(CravingLibrary.cuisine(id: "sushi")!, name: "O-Ku"))
    }

    @Test func matchingPlacesComeFirstThenNearest() {
        let thai = CravingLibrary.cuisine(id: "thai")!
        let result = CravingPicker.places(for: thai, candidates: [
            place("Burger Joint", metersNorth: 100),
            place("Thai Taste", metersNorth: 3_000),
            place("Taco Spot", metersNorth: 50)
        ], origin: origin, maxDistanceMeters: 10_000, sources: Set(WidgetPlaceSource.allCases))
        #expect(result.map(\.scored.candidate.name) == ["Thai Taste", "Taco Spot", "Burger Joint"])
        #expect(result.first?.matchesCuisine == true)
        #expect(result.dropFirst().allSatisfy { !$0.matchesCuisine })
    }
}

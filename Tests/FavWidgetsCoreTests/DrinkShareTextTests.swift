import Testing
import Foundation
@testable import FavWidgetsCore

struct DrinkShareTextTests {
    private let paperPlane = CocktailLibrary.cocktail(id: "paper-plane")!

    @Test func shareTextListsTheRecipe() {
        let text = DrinkShareText.shareText(paperPlane)
        #expect(text.hasPrefix("Paper Plane\n"))
        #expect(text.contains("• ¾ bourbon"))
        #expect(text.hasSuffix("From Make Me a Drink on FavCircles"))
    }

    @Test func notesAreTrimmedAndCapped() {
        #expect(DrinkShareText.cleanNote("   ") == nil)
        #expect(DrinkShareText.cleanNote("  try this ") == "try this")
        #expect(DrinkShareText.cleanNote(String(repeating: "x", count: 300))?.count == DrinkShareText.noteLimit)
    }

    @Test func confirmationMentionsTheBonusOnlyWhenPaid() {
        #expect(DrinkShareText.sentConfirmation(drinkName: "Paper Plane", recipientName: "Sal", recipientCredited: false)
                == "Sent a Paper Plane to Sal.")
        #expect(DrinkShareText.sentConfirmation(drinkName: "Old Fashioned", recipientName: "Sal", recipientCredited: true)
                == "Sent an Old Fashioned to Sal. They got 1 FavCoin 🌵 from FavCircles too.")
    }
}

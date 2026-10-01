import Foundation

/// The words around sharing and sending a drink recipe.
///
/// Sharing and sending are private (a share sheet, a chat message): nothing
/// about drinks is ever posted to a feed (Wes, 2026-10-01).
public enum DrinkShareText {
    /// Longest personal note on a sent drink (the server's limit too).
    public static let noteLimit = 200

    /// What goes to the share sheet alongside the card image.
    public static func shareText(_ drink: Cocktail) -> String {
        let ingredients = drink.ingredients.map { "• \($0.line)" }.joined(separator: "\n")
        return "\(drink.name)\n\(ingredients)\n\nFrom Make Me a Drink on FavCircles"
    }

    /// The note to send: trimmed, cut to the limit; nil when empty.
    public static func cleanNote(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(noteLimit))
    }

    /// After a send: "Sent a Paper Plane to Sal." plus the FavCircles bonus
    /// line when the server paid one to the recipient.
    public static func sentConfirmation(drinkName: String, recipientName: String, recipientCredited: Bool) -> String {
        let sent = "Sent \(article(for: drinkName)) \(drinkName) to \(recipientName)."
        return recipientCredited ? "\(sent) They got 1 FavCoin 🌵 from FavCircles too." : sent
    }

    static func article(for name: String) -> String {
        guard let first = name.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }
}

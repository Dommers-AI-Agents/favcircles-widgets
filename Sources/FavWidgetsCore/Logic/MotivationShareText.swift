import Foundation

/// The words around sending Coach Mane's line to someone: the share-sheet
/// text, the chat message a FavCircles friend gets, and the confirmation.
public enum MotivationShareText {
    public static let appStoreURL = "https://apps.apple.com/us/app/favcircles/id6746807095"
    /// Longest line the server takes (the longest real line is well under).
    public static let lineLimit = 160

    /// Alongside the card image in the share sheet.
    public static func shareText(line: String) -> String {
        "📣 Coach Mane says: \(line)\n\nGet Coach Mane on FavCircles: \(appStoreURL)"
    }

    /// The chat message text: also what the friend's push and chat list show.
    public static func chatText(line: String) -> String {
        "📣 Coach Mane says: \(line)"
    }

    /// The card's caption under the speech bubble.
    public static let cardCaption = "Someone thinks you need to hear this."

    public static func sentConfirmation(recipientName: String) -> String {
        "Sent to \(recipientName). Coach Mane will take it from here."
    }
}

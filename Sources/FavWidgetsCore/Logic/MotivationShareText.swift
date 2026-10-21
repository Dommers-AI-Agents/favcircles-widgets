import Foundation

/// The words around sending Coach Mane's line to someone: the share-sheet
/// text, the chat message a FavCircles friend gets, and the confirmation.
public enum MotivationShareText {
    public static let appStoreURL = "https://apps.apple.com/us/app/favcircles/id6746807095"
    /// Longest line the server takes (the longest real line is well under).
    public static let lineLimit = 160

    /// The "go to the gym" video (Wes, 2026-10-21): played on the widget's main
    /// screen and linked wherever a line is shared, so the friend gets its thumbnail too.
    public static let gymVideoURL = "https://www.tiktok.com/t/ZTfBJR7gQ/"
    public static let gymVideoID = "7142494499367931179"
    public static let gymVideoPlayerURL = "https://www.tiktok.com/player/v1/\(gymVideoID)?autoplay=0&music_info=0&description=0"
    public static let gymVideoCaption = "▶ Go to the gym"
    public static let gymVideoLinkLine = "\(gymVideoCaption): \(gymVideoURL)"

    /// Only when there's no card image to share (the card is the message).
    public static func shareText(line: String) -> String {
        "📣 Coach Mane says: \(line)\n\(gymVideoLinkLine)"
    }

    /// The link title Messages shows under the card.
    public static let shareTitle = "Coach Mane · FavCircles"

    /// The chat message text: also what the friend's push and chat list show.
    public static func chatText(line: String) -> String {
        "📣 Coach Mane says: \(line)\n\(gymVideoLinkLine)"
    }

    /// The card's caption under the speech bubble.
    public static let cardCaption = "Someone thinks you need to hear this."

    public static func sentConfirmation(recipientName: String) -> String {
        "Sent to \(recipientName). Coach Mane will take it from here."
    }
}

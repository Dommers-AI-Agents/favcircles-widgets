import Foundation

/// The link a quote's Share button hands out.
///
/// Shared as a bare URL on purpose: Messages turns it into a compact card
/// (the quote as its title, the app icon beside it) built from the landing
/// page's tags, and the card is tappable. With the app installed the link
/// opens the reel on this quote (the app claims `api.favcircles.com/app/*`);
/// without it the page shows the quote and the way to get more. Sending the
/// quote as text as well would print it twice, once in a bubble and once in
/// the card.
///
/// `api.favcircles.com`, not `favcircles.com`: only the api host is an
/// associated domain for app links (the app's `WidgetShareLink` has the full
/// story).
public enum QuoteShareLink {
    public static let base = "https://api.favcircles.com/app/quote/"

    /// nil for an id that can't sit in a path — catalog ids are slugs, but a
    /// share button must never hand out a broken URL.
    public static func url(quoteId: String) -> URL? {
        let trimmed = quoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: allowed.inverted) == nil else { return nil }
        return URL(string: base + trimmed)
    }

    /// What to share: the link alone, or the quote as text when no link can
    /// be built, so Share never goes silent.
    public static func items(for quote: QuoteReelItem) -> [WidgetShareItem] {
        if let url = url(quoteId: quote.id) { return [.url(url)] }
        let line = quote.attribution.map { "\(quote.text)\n\($0)" } ?? quote.text
        return [.text(line)]
    }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
}

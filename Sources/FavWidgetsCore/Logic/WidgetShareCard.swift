import Foundation

/// What Share sends for a widget's card: ONE Messages bubble — the card image
/// as a tappable link that opens the widget (or the App Store for someone
/// without FavCircles). Not the card plus a text bubble repeating it plus an
/// App Store preview (Wes, 2026-10-05: "This is obnoxious").
/// Without a card image, the text alone, so Share never goes silent.
public enum WidgetShareCard {
    public static let base = "https://api.favcircles.com/app/widget/"

    public static func url(widgetId: String) -> URL? { URL(string: base + widgetId) }

    public static func items(widgetId: String, title: String, cardJPEG: Data?, fallbackText: String) -> [WidgetShareItem] {
        if let url = url(widgetId: widgetId), let cardJPEG { return [.link(url, title: title, imageJPEG: cardJPEG)] }
        if let cardJPEG { return [.imageJPEG(cardJPEG)] }
        return [.text(fallbackText)]
    }
}

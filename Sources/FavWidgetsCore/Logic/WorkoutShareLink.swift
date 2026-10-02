import Foundation

/// What Share sends for a finished workout. One bubble: the card image as a
/// link that opens this workout in the Workouts widget — not the card plus a
/// wall of text (Wes, 2026-10-02). Without a link (offline) the card alone;
/// without even a card, the text, so Share never goes silent.
public enum WorkoutShareLink {
    public static func items(url: URL?, summary: WorkoutShareSummary, cardJPEG: Data?,
                             calendar: Calendar = .current) -> [WidgetShareItem] {
        if let url { return [.link(url, title: title(summary), imageJPEG: cardJPEG)] }
        if let cardJPEG { return [.imageJPEG(cardJPEG)] }
        return [.text(summary.shareText(calendar: calendar))]
    }

    /// The link's title where Messages shows one: "Chest and Back · 78 min"
    public static func title(_ summary: WorkoutShareSummary) -> String {
        "\(summary.name) · \(max(1, summary.durationSeconds / 60)) min"
    }
}

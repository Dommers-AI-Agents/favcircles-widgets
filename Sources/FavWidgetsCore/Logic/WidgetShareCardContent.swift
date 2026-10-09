import Foundation

/// What a widget's share card shows (Wes, 2026-10-09: every widget has a
/// share card; the content is minimal but says what was shared, and the link
/// brings the recipient back to the app and that widget).
///
/// A widget with something worth showing (a run, a quote) supplies one from
/// `FavWidget.shareCard(context:)`; every other widget gets `generic`, a card
/// naming the widget and what it does. Never personal data the user didn't
/// choose to show — health, contacts, packages and the like share the
/// generic card.
public struct WidgetShareCardContent: Equatable, Sendable {
    public struct Stat: Equatable, Sendable {
        public let value: String
        public let label: String
        public init(_ value: String, _ label: String) { self.value = value; self.label = label }
    }

    /// The big line: "2.28 mi run", "New Contacts".
    public var headline: String
    /// One short line under it: a date, or what the widget does.
    public var detail: String?
    /// Up to four numbers across the card.
    public var stats: [Stat]
    /// A picture on the card (a route map).
    public var imageJPEG: Data?
    /// The link's title where Messages shows one.
    public var linkTitle: String
    /// Where the card leads; nil = the widget's page (/app/widget/<id>).
    public var url: URL?

    public init(headline: String, detail: String? = nil, stats: [Stat] = [], imageJPEG: Data? = nil,
                linkTitle: String, url: URL? = nil) {
        self.headline = headline
        self.detail = detail
        self.stats = Array(stats.prefix(4))
        self.imageJPEG = imageJPEG
        self.linkTitle = linkTitle
        self.url = url
    }

    /// The card for a widget with nothing specific to show.
    public static func generic(_ descriptor: FavWidgetDescriptor) -> WidgetShareCardContent {
        WidgetShareCardContent(headline: descriptor.title, detail: descriptor.shareText,
                               linkTitle: "\(descriptor.title) · FavCircles")
    }

    /// A finished run: "2.28 mi run" · date · distance / time / pace.
    public static func run(_ record: RunRecord, unit: RunUnit, mapJPEG: Data?, calendar: Calendar = .current) -> WidgetShareCardContent {
        let distance = RunMath.distanceText(record.distanceMeters, unit: unit)
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return WidgetShareCardContent(
            headline: "\(distance) \(unit.label) run",
            detail: f.string(from: record.startedAt),
            stats: [.init(distance, unit.label), .init(RunMath.clock(record.movingSeconds), "time"),
                    .init(RunMath.paceText(record.pace(unit)), "/\(unit.label)")],
            imageJPEG: mapJPEG,
            linkTitle: "\(distance) \(unit.label) run · FavRun")
    }
}

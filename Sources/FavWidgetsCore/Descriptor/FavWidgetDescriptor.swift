import Foundation

/// Where a widget sits in the tab's grouping and in Manage.
public enum FavWidgetCategory: String, Codable, CaseIterable, Sendable {
    case health, fitness, money, social
}

/// How a widget stores its data (see `WidgetShardPlanner`).
///
/// - `single`: one document for all time (compact, counter-style data).
/// - `monthly`: a small settings document under the widget id plus one log
///   document per month (`<id>_YYYY-MM`) for entry-style data that grows.
public enum FavWidgetStorage: String, Codable, Sendable {
    case single, monthly
}

/// The static identity of a widget. `id` doubles as the backend document
/// key, so it is lowercase and stable forever.
public struct FavWidgetDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// SF Symbol name.
    public let symbolName: String
    /// "#RRGGBB"; the UI layer turns it into a Color.
    public let accentHex: String
    public let category: FavWidgetCategory
    public let storage: FavWidgetStorage
    public let defaultEnabled: Bool
    /// Bump when the Codable model changes shape; stamped on every save so
    /// a future migration knows what it is reading.
    public let schemaVersion: Int
    /// The line after "<title> on FavCircles — " in the share sheet, when the
    /// card's subtitle isn't the right pitch for someone who doesn't have the
    /// app. Absent, the subtitle is used.
    public let shareBlurb: String?

    /// What the share message says about the widget.
    public var shareText: String { shareBlurb ?? subtitle }

    public init(
        id: String,
        title: String,
        subtitle: String,
        symbolName: String,
        accentHex: String,
        category: FavWidgetCategory,
        storage: FavWidgetStorage = .single,
        defaultEnabled: Bool = true,
        schemaVersion: Int = 1,
        shareBlurb: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.category = category
        self.storage = storage
        self.defaultEnabled = defaultEnabled
        self.schemaVersion = schemaVersion
        self.shareBlurb = shareBlurb
    }

    /// Backend document-key rule (mirrors `WIDGET_ID_RE` server-side).
    public static let idPattern = "^[a-z][a-z0-9_-]{1,47}$"

    public static func isValidId(_ id: String) -> Bool {
        id.range(of: idPattern, options: .regularExpression) != nil
    }
}

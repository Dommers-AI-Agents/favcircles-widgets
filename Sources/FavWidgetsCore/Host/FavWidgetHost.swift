import Foundation

/// A person the user can send things to (an accepted connection).
public struct WidgetContact: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let avatarURL: URL?

    public init(id: String, displayName: String, avatarURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

/// A lightweight pointer to a FavCircles place.
public struct WidgetPlaceRef: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let city: String?
    /// True when `id` is a canonical globalPlaces id (vs a save-record id).
    public let isGlobal: Bool

    public init(id: String, name: String, city: String? = nil, isGlobal: Bool = true) {
        self.id = id
        self.name = name
        self.city = city
        self.isGlobal = isGlobal
    }
}

public struct WidgetAnalyticsEvent: Sendable {
    public let name: String
    public let parameters: [String: String]

    public init(_ name: String, _ parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

public enum WidgetHaptic: Sendable {
    case light, medium, success, warning, selection
}

public enum WidgetShareItem: Sendable {
    case text(String)
    case imageJPEG(Data)
    case url(URL)
}

public struct WidgetAlert: Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// Everything the postcard widget hands the app to deliver.
public struct WidgetPostcardSend: Sendable {
    public let recipientId: String
    public let imageJPEG: Data
    public let message: String
    public let templateId: String
    public let place: WidgetPlaceRef?

    public init(recipientId: String, imageJPEG: Data, message: String, templateId: String, place: WidgetPlaceRef?) {
        self.recipientId = recipientId
        self.imageJPEG = imageJPEG
        self.message = message
        self.templateId = templateId
        self.place = place
    }
}

public struct WidgetPostcardReceipt: Sendable {
    public let messageId: String
    public let conversationId: String
    public let imageURL: URL?

    public init(messageId: String, conversationId: String, imageURL: URL?) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.imageURL = imageURL
    }
}

/// What a widget may ask of the app. No UIKit types cross this boundary
/// (`Data`, not `UIImage`) so the core stays testable on a Mac and the app
/// owns every presentation decision.
public protocol FavWidgetHost: AnyObject {
    var dataStore: WidgetDataStore { get }
    var currentUserId: String? { get }

    func track(_ event: WidgetAnalyticsEvent)
    func haptic(_ kind: WidgetHaptic)
    func openURL(_ url: URL)
    func share(_ items: [WidgetShareItem])
    func presentAlert(_ alert: WidgetAlert)

    /// The user's accepted connections.
    func fetchConnections() async throws -> [WidgetContact]
    /// Uploads the rendered postcard and delivers it as a message.
    func sendPostcard(_ postcard: WidgetPostcardSend) async throws -> WidgetPostcardReceipt
    /// A place the user is at or near right now, if the app knows one.
    func nearbyOrCurrentPlace() async -> WidgetPlaceRef?

    // MARK: Places (added in 0.2.0)

    /// The device's current location, or nil when unavailable/denied.
    func currentLocation() async -> WidgetCoordinate?
    /// Saved places matching `query` from the user's own lists and the
    /// people they're connected to / follow.
    func fetchPlaces(_ query: WidgetPlaceQuery) async throws -> [WidgetPlaceCandidate]
    /// Opens the place's page in the app.
    func openPlace(_ place: WidgetPlaceRef)
}

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


// MARK: - Payment (0.5.0)

/// What the app needs to put a payment sheet on screen. Deliberately carries
/// no Stripe type: the widget package never imports a payment SDK, so the app
/// can change processor without the widgets knowing.
public struct WidgetPaymentRequest: Sendable {
    public let publishableKey: String
    public let merchantDisplayName: String
    public let applePayMerchantId: String
    public let amountCents: Int
    public let currency: String
    /// The single line item shown in the Wallet sheet.
    public let summaryLabel: String

    /// Produces the payment's client secret, called *after* the wallet
    /// authorizes.
    ///
    /// This is a closure rather than a value because Apple requires the
    /// payment sheet to be presented directly from the user's tap, "before
    /// any asynchronous or long-running code". Creating the order up front
    /// and passing a secret in would put a network round trip in front of the
    /// sheet and Apple Pay would refuse to appear.
    public let clientSecret: @Sendable () async throws -> String

    public init(publishableKey: String, merchantDisplayName: String, applePayMerchantId: String,
                amountCents: Int, currency: String, summaryLabel: String,
                clientSecret: @escaping @Sendable () async throws -> String) {
        self.publishableKey = publishableKey
        self.merchantDisplayName = merchantDisplayName
        self.applePayMerchantId = applePayMerchantId
        self.amountCents = amountCents
        self.currency = currency
        self.summaryLabel = summaryLabel
        self.clientSecret = clientSecret
    }
}

public enum WidgetPaymentResult: Sendable {
    case completed
    /// The person dismissed the wallet. Not an error, and nothing was held.
    case canceled
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

    // MARK: API channel (added in 0.3.0)

    /// An authenticated call to the FavCircles API on the widget's behalf.
    /// Paths are relative ("widgets/nextbar/rounds") and the app only
    /// allows the `widgets/` prefix, so a widget can own its own endpoints
    /// without an app change.
    func request(_ request: WidgetAPIRequest) async throws -> Data

    // MARK: Media (added in 0.4.0)

    /// Uploads a JPEG through the app's image pipeline; returns its public URL.
    /// That pipeline compresses and may downsize, which is right for anything
    /// shown on a screen and wrong for anything going to a printer.
    func uploadImage(_ jpeg: Data) async throws -> URL

    // MARK: Paid print (added in 0.5.0)

    /// Uploads print-resolution artwork with no resizing and a larger size
    /// cap. Separate from `uploadImage` because the ordinary path would
    /// silently reduce a 1875x1275 card to 1280px and ruin the print.
    func uploadPrintImage(_ jpeg: Data) async throws -> URL

    /// False when this device can't pay at all (no wallet, no card). Paid
    /// options are hidden rather than shown as dead buttons.
    var supportsPayment: Bool { get }

    /// Presents the payment sheet and waits for the person to finish with it.
    /// Must be called straight from a user gesture.
    func collectPayment(_ request: WidgetPaymentRequest) async throws -> WidgetPaymentResult
}

public struct WidgetAPIRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }
    public let method: Method
    public let path: String
    /// JSON body, already encoded.
    public let body: Data?

    public init(_ method: Method, _ path: String, body: Data? = nil) {
        self.method = method
        self.path = path
        self.body = body
    }
}

public struct WidgetAPIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String?
    public let message: String

    public init(status: Int, code: String? = nil, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

import Foundation

/// Records every host call. Used by package tests, previews, and the app's
/// own tests.
public final class MockWidgetHost: FavWidgetHost, @unchecked Sendable {
    public let dataStore: WidgetDataStore
    public var currentUserId: String?

    public private(set) var events: [WidgetAnalyticsEvent] = []
    public private(set) var haptics: [WidgetHaptic] = []
    public private(set) var openedURLs: [URL] = []
    public private(set) var shared: [[WidgetShareItem]] = []
    public private(set) var alerts: [WidgetAlert] = []
    public private(set) var sentPostcards: [WidgetPostcardSend] = []

    public var connections: [WidgetContact] = []
    public var connectionsError: Error?
    public var postcardError: Error?
    public var nearbyPlace: WidgetPlaceRef?

    public init(dataStore: WidgetDataStore = InMemoryWidgetDataStore(), currentUserId: String? = "test-user") {
        self.dataStore = dataStore
        self.currentUserId = currentUserId
    }

    public func track(_ event: WidgetAnalyticsEvent) { events.append(event) }
    public func haptic(_ kind: WidgetHaptic) { haptics.append(kind) }
    public func openURL(_ url: URL) { openedURLs.append(url) }
    public func share(_ items: [WidgetShareItem]) { shared.append(items) }
    public func presentAlert(_ alert: WidgetAlert) { alerts.append(alert) }

    public func fetchConnections() async throws -> [WidgetContact] {
        if let connectionsError { throw connectionsError }
        return connections
    }

    public func sendPostcard(_ postcard: WidgetPostcardSend) async throws -> WidgetPostcardReceipt {
        if let postcardError { throw postcardError }
        sentPostcards.append(postcard)
        return WidgetPostcardReceipt(messageId: "msg_\(sentPostcards.count)", conversationId: "conv_1", imageURL: nil)
    }

    public func nearbyOrCurrentPlace() async -> WidgetPlaceRef? { nearbyPlace }

    public var location: WidgetCoordinate?
    public var places: [WidgetPlaceCandidate] = []
    public var placesError: Error?
    public private(set) var openedPlaces: [WidgetPlaceRef] = []
    public private(set) var placeQueries: [WidgetPlaceQuery] = []

    public func currentLocation() async -> WidgetCoordinate? { location }

    public func fetchPlaces(_ query: WidgetPlaceQuery) async throws -> [WidgetPlaceCandidate] {
        placeQueries.append(query)
        if let placesError { throw placesError }
        return places.filter { candidate in
            (query.categories.isEmpty || query.categories.contains(candidate.category)) && query.sources.contains(candidate.source)
        }
    }

    public func openPlace(_ place: WidgetPlaceRef) { openedPlaces.append(place) }

    public private(set) var uploadedImages: [Data] = []
    public var uploadError: Error?

    public func uploadImage(_ jpeg: Data) async throws -> URL {
        if let uploadError { throw uploadError }
        uploadedImages.append(jpeg)
        return URL(string: "https://example.test/uploads/\(uploadedImages.count).jpg")!
    }

    public private(set) var uploadedPrintImages: [Data] = []
    public var printUploadError: Error?

    public func uploadPrintImage(_ jpeg: Data) async throws -> URL {
        if let printUploadError { throw printUploadError }
        uploadedPrintImages.append(jpeg)
        return URL(string: "https://example.test/print/\(uploadedPrintImages.count).jpg")!
    }

    /// Scripted API responses keyed by "METHOD path"; unscripted calls throw 404.
    public var apiResponses: [String: Data] = [:]
    public private(set) var apiRequests: [WidgetAPIRequest] = []

    public func request(_ request: WidgetAPIRequest) async throws -> Data {
        apiRequests.append(request)
        if let data = apiResponses["\(request.method.rawValue) \(request.path)"] { return data }
        throw WidgetAPIError(status: 404, message: "No scripted response for \(request.method.rawValue) \(request.path)")
    }
}

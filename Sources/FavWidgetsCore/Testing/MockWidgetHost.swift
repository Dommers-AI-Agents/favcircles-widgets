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
}

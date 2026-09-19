import Foundation
import FavWidgetsCore

enum QuotesAPI {
    static func settings(context: WidgetContext) async throws -> QuoteSettingsResponse {
        try WidgetJSON.decode(QuoteSettingsResponse.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/quotes/settings")))
    }

    /// Only the fields being changed are sent; the server merges the rest.
    static func update(context: WidgetContext, enabled: Bool? = nil, categories: [String]? = nil,
                       time: String? = nil, email: Bool? = nil) async throws -> QuoteSettingsResponse {
        var body: [String: Any] = [:]
        if let enabled { body["enabled"] = enabled }
        if let categories { body["categories"] = categories }
        if let time { body["time"] = time }
        if let email { body["email"] = email }
        let encoded = try? JSONSerialization.data(withJSONObject: body)
        return try WidgetJSON.decode(QuoteSettingsResponse.self,
                                     from: await context.host.request(WidgetAPIRequest(.put, "widgets/quotes/settings", body: encoded)))
    }
}

@MainActor
final class QuotesStore: ObservableObject {
    @Published var prefs = QuoteSettings()
    @Published var categories: [QuoteCategory] = []
    @Published var today: DailyQuote?
    @Published var loadError: String?
    private var loaded = false

    private static var stores: [String: QuotesStore] = [:]
    static func shared(_ context: WidgetContext) -> QuotesStore {
        let key = context.descriptor.id
        if let existing = stores[key] { return existing }
        let store = QuotesStore()
        stores[key] = store
        return store
    }

    func loadIfNeeded(context: WidgetContext) async {
        guard !loaded else { return }
        await load(context: context)
    }

    func load(context: WidgetContext) async {
        do {
            apply(try await QuotesAPI.settings(context: context))
            loadError = nil
            loaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    func apply(_ response: QuoteSettingsResponse) {
        prefs = response.prefs
        if !response.categories.isEmpty { categories = response.categories }
        today = response.today ?? today
    }
}

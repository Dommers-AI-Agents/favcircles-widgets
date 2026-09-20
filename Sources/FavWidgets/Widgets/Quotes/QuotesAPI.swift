import Foundation
import FavWidgetsCore

enum QuotesAPI {
    static func settings(context: WidgetContext) async throws -> QuoteSettingsResponse {
        try WidgetJSON.decode(QuoteSettingsResponse.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/quotes/settings")))
    }

    /// Only the fields being changed are sent; the server merges the rest.
    static func update(context: WidgetContext, enabled: Bool? = nil, categories: [String]? = nil,
                       times: [String]? = nil, email: Bool? = nil) async throws -> QuoteSettingsResponse {
        var body: [String: Any] = [:]
        if let enabled { body["enabled"] = enabled }
        if let categories { body["categories"] = categories }
        if let times { body["times"] = times; body["time"] = times.first ?? "08:00" }
        if let email { body["email"] = email }
        return try await context.api(.put, "widgets/quotes/settings", body: body)
    }
}

@MainActor
final class QuotesStore: RemoteStore {
    @Published var prefs = QuoteSettings()
    @Published var categories: [QuoteCategory] = []
    @Published var today: DailyQuote?

    /// Lives with the widget's context like the other stores (a static
    /// dictionary here used to outlive the context and never emptied).
    static func shared(_ context: WidgetContext) -> QuotesStore {
        context.transient("quotes.store") { QuotesStore() }
    }

    func loadIfNeeded(context: WidgetContext) async {
        await loadIfNeeded { self.apply(try await QuotesAPI.settings(context: context)) }
    }

    func load(context: WidgetContext) async {
        await load { self.apply(try await QuotesAPI.settings(context: context)) }
    }

    func apply(_ response: QuoteSettingsResponse) {
        prefs = response.prefs
        if !response.categories.isEmpty { categories = response.categories }
        today = response.today ?? today
    }
}

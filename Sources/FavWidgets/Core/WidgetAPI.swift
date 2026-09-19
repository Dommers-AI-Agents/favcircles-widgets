import Foundation
import FavWidgetsCore

/// The one way a widget calls its own endpoints: JSON in, decoded model out.
/// A body that can't be encoded THROWS here; the per-widget copies this
/// replaces used `try?`, which sent the request with no body and let the
/// server report a confusing "missing field" instead of the real error.
public extension WidgetContext {
    func api<T: Decodable>(_ method: WidgetAPIRequest.Method, _ path: String, body: [String: Any]? = nil) async throws -> T {
        try WidgetJSON.decode(T.self, from: await apiData(method, path, body: body))
    }

    /// Same call when the response body isn't needed (or is decoded by hand).
    func apiData(_ method: WidgetAPIRequest.Method, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        let encoded = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await host.request(WidgetAPIRequest(method, path, body: encoded))
    }
}

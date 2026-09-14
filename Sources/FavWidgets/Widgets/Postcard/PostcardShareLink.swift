import Foundation
import FavWidgetsCore

/// Publishes a rendered postcard as a public web page via the app's upload
/// pipeline and `POST widgets/postcard/share`. Returns nil on any failure
/// so sharing can fall back to the bare image.
enum PostcardShareLink {
    private struct Response: Decodable { let url: String }

    static func create(context: WidgetContext, jpeg: Data, message: String, templateId: String, place: WidgetPlaceRef?) async -> URL? {
        do {
            let imageURL = try await context.host.uploadImage(jpeg)
            var body: [String: Any] = ["imageUrl": imageURL.absoluteString, "message": message, "templateId": templateId]
            if let place {
                var ref: [String: Any] = ["name": place.name]
                if let city = place.city { ref["city"] = city }
                body["placeRef"] = ref
            }
            let data = try await context.host.request(WidgetAPIRequest(.post, "widgets/postcard/share", body: try JSONSerialization.data(withJSONObject: body)))
            return URL(string: try JSONDecoder().decode(Response.self, from: data).url)
        } catch {
            return nil
        }
    }
}

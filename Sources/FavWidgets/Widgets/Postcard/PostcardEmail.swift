import Foundation
import FavWidgetsCore

/// "Send by email": the app mails the card to addresses the user typed in
/// (`POST widgets/postcard/email`), which also publishes the public page.
enum PostcardEmail {
    struct Result: Decodable {
        let url: String?
        let sent: [String]
        let failed: [String]?
    }

    static let maxAddresses = 5

    /// Splits "a@x.com, b@y.org" into trimmed, lowercased, de-duplicated
    /// addresses; `invalid` holds anything that doesn't look like an email.
    static func parse(_ text: String) -> (valid: [String], invalid: [String]) {
        var valid: [String] = []
        var invalid: [String] = []
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
        for part in parts {
            let address = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !address.isEmpty else { continue }
            if isValid(address) {
                if !valid.contains(address) { valid.append(address) }
            } else {
                invalid.append(address)
            }
        }
        return (valid, invalid)
    }

    static func isValid(_ address: String) -> Bool {
        address.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil && address.count <= 254
    }

    static func send(context: WidgetContext, jpeg: Data, emails: [String], message: String, templateId: String, place: WidgetPlaceRef?) async throws -> Result {
        let imageURL = try await context.host.uploadImage(jpeg)
        var body: [String: Any] = ["imageUrl": imageURL.absoluteString, "message": message, "templateId": templateId, "emails": emails]
        if let place {
            var ref: [String: Any] = ["name": place.name]
            if let city = place.city { ref["city"] = city }
            body["placeRef"] = ref
        }
        let data = try await context.host.request(WidgetAPIRequest(.post, "widgets/postcard/email", body: try JSONSerialization.data(withJSONObject: body)))
        return try JSONDecoder().decode(Result.self, from: data)
    }
}

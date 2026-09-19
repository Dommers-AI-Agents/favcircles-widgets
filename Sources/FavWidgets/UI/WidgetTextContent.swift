import SwiftUI

/// Text-content hints, wrapped so this file compiles on macOS where
/// `UITextContentType` doesn't exist.
enum WidgetTextContent {
    case name, streetAddressLine1, streetAddressLine2, addressCity, postalCode

    #if os(iOS)
    var uiContentType: UITextContentType {
        switch self {
        case .name: return .name
        case .streetAddressLine1: return .streetAddressLine1
        case .streetAddressLine2: return .streetAddressLine2
        case .addressCity: return .addressCity
        case .postalCode: return .postalCode
        }
    }
    #endif
}

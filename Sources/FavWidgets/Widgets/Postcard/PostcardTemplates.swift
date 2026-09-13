import SwiftUI
import FavWidgetsCore

#if canImport(UIKit)
import UIKit
/// The in-memory photo type on each platform. Never stored in a model.
public typealias PostcardPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PostcardPlatformImage = NSImage
#endif

extension Image {
    init(postcardImage: PostcardPlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: postcardImage)
        #else
        self.init(nsImage: postcardImage)
        #endif
    }
}

/// The four looks a postcard can have; all drawn in SwiftUI, no assets.
/// `rawValue` is what `PostcardSettings.lastTemplateId` and every record
/// store, so the cases are stable forever.
enum PostcardTemplate: String, CaseIterable, Identifiable {
    case classic, vintage, modern, polaroid

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .vintage: return "Vintage"
        case .modern: return "Modern"
        case .polaroid: return "Polaroid"
        }
    }

    /// Unknown ids (an older app, a typo in a record) fall back to classic.
    static func resolve(_ id: String) -> PostcardTemplate {
        PostcardTemplate(rawValue: id) ?? .classic
    }

    /// Photo aspect the templates are designed around (a 6x4 postcard).
    static let aspectRatio: CGFloat = 3.0 / 2.0
}

/// Small shared helpers for postcard copy.
enum PostcardCopy {
    static let messageLimit = 500

    /// "Greetings from Lisbon"; empty when no place is known.
    static func caption(placeName: String) -> String {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "Greetings from \(trimmed)"
    }

    /// "Sent to Ana · Lisbon · 3 days ago"
    static func summary(for record: PostcardRecord, now: Date = Date()) -> String {
        var parts = ["Sent to \(record.recipientName)"]
        if let place = record.place?.name, !place.isEmpty { parts.append(place) }
        parts.append(relative(record.sentAt, now: now))
        return parts.joined(separator: " · ")
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Id used for a place the user typed that isn't a FavCircles place.
    /// Kept in drafts/records so the name survives; never sent to the host.
    static let customPlaceId = ""

    static func isCustom(_ place: WidgetPlaceRef?) -> Bool {
        place?.id == customPlaceId
    }
}

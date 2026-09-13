import Foundation

/// Per-user tab layout: which widgets show and in what order. Stored under
/// the reserved document id `prefs` through the same store as everything
/// else.
public struct WidgetPreferences: WidgetModel {
    public static let documentId = "prefs"
    public static let schemaVersion = 1

    /// Widget ids in display order. Ids not listed follow in registry order.
    public var order: [String]
    public var disabled: Set<String>
    /// Hint keys the user has dismissed (per account, not per device).
    public var seenHints: Set<String>

    public init(order: [String] = [], disabled: Set<String> = [], seenHints: Set<String> = []) {
        self.order = order
        self.disabled = disabled
        self.seenHints = seenHints
    }

    public static let empty = WidgetPreferences()

    public static func merge(local: WidgetPreferences, remote: WidgetPreferences) -> WidgetPreferences {
        // Layout: local wins. Hints: union, a dismissed hint stays dismissed.
        WidgetPreferences(order: local.order, disabled: local.disabled,
                          seenHints: local.seenHints.union(remote.seenHints))
    }

    public func isEnabled(_ descriptor: FavWidgetDescriptor) -> Bool {
        if disabled.contains(descriptor.id) { return false }
        return descriptor.defaultEnabled || order.contains(descriptor.id)
    }

    public mutating func setEnabled(_ enabled: Bool, id: String) {
        if enabled {
            disabled.remove(id)
            if !order.contains(id) { order.append(id) }
        } else {
            disabled.insert(id)
        }
    }
}

public enum WidgetOrdering {
    /// Every registered widget in the user's order (disabled ones included),
    /// unknown ids dropped, unlisted widgets appended in registry order.
    public static func all(prefs: WidgetPreferences, descriptors: [FavWidgetDescriptor]) -> [FavWidgetDescriptor] {
        let byId = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [FavWidgetDescriptor] = []
        for id in prefs.order {
            guard let descriptor = byId[id], !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(descriptor)
        }
        for descriptor in descriptors where !seen.contains(descriptor.id) {
            result.append(descriptor)
        }
        return result
    }

    /// The widgets that should render on the tab.
    public static func visible(prefs: WidgetPreferences, descriptors: [FavWidgetDescriptor]) -> [FavWidgetDescriptor] {
        all(prefs: prefs, descriptors: descriptors).filter { prefs.isEnabled($0) }
    }
}

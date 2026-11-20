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
    /// List (one card per widget) or tiles (a grid, more on screen); optional
    /// so documents saved before the toggle existed still decode (Wes,
    /// 2026-11-20: "a toggle view between list and tile view").
    public var layout: WidgetTabLayout?

    public init(order: [String] = [], disabled: Set<String> = [], seenHints: Set<String> = [], layout: WidgetTabLayout? = nil) {
        self.order = order
        self.disabled = disabled
        self.seenHints = seenHints
        self.layout = layout
    }

    public var tabLayout: WidgetTabLayout { layout ?? .list }

    public static let empty = WidgetPreferences()

    public static func merge(local: WidgetPreferences, remote: WidgetPreferences) -> WidgetPreferences {
        // Layout: local wins. Hints: union, a dismissed hint stays dismissed.
        WidgetPreferences(order: local.order, disabled: local.disabled,
                          seenHints: local.seenHints.union(remote.seenHints), layout: local.layout ?? remote.layout)
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

    /// A new full order after the user drags a card on the tab, where only
    /// the visible (enabled) widgets are on screen. `source`/`destination`
    /// are List `onMove` offsets into `visibleIds`. Disabled widgets keep
    /// their slots; the visible ones are re-dealt into the visible slots in
    /// the new order, so Manage and the tab always agree.
    public static func movingVisible(all: [String], visibleIds: [String], fromOffsets source: IndexSet, toOffset destination: Int) -> [String] {
        let picked = source.sorted().compactMap { $0 < visibleIds.count ? visibleIds[$0] : nil }
        var reordered = visibleIds.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let removedBefore = source.filter { $0 < destination }.count
        reordered.insert(contentsOf: picked, at: max(0, min(reordered.count, destination - removedBefore)))
        let visibleSet = Set(visibleIds)
        var next = reordered.makeIterator()
        return all.map { id in visibleSet.contains(id) ? (next.next() ?? id) : id }
    }
}

/// How the Widgets tab lays its widgets out.
public enum WidgetTabLayout: String, Codable, Sendable, CaseIterable {
    case list, tiles

    public var toggled: WidgetTabLayout { self == .list ? .tiles : .list }
    /// The toggle button shows what tapping switches TO.
    public var toggleSymbolName: String { self == .list ? "square.grid.2x2" : "list.bullet" }
    public var toggleTitle: String { self == .list ? "Tiles" : "List" }
}

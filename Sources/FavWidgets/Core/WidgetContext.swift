import SwiftUI
import FavWidgetsCore

/// Holds one `WidgetStateController` per document id so a widget's card and
/// full view (and the tab's preload) share the same in-memory model.
@MainActor
public final class WidgetStateCache {
    private var controllers: [String: AnyObject] = [:]
    private let store: WidgetDataStore

    public init(store: WidgetDataStore) {
        self.store = store
    }

    public func controller<M: WidgetModel>(_ type: M.Type, documentId: String, schemaVersion: Int) -> WidgetStateController<M> {
        if let existing = controllers[documentId] as? WidgetStateController<M> {
            return existing
        }
        let controller = WidgetStateController<M>(documentId: documentId, schemaVersion: schemaVersion, store: store)
        controllers[documentId] = controller
        return controller
    }

    /// Every controller created so far, for flush/refresh sweeps.
    public var all: [any WidgetSyncing] {
        controllers.values.compactMap { $0 as? any WidgetSyncing }
    }
}

/// Type-erased view of a state controller for sweeps.
@MainActor
public protocol WidgetSyncing: AnyObject {
    var documentId: String { get }
    func flush() async
    func reload() async
    func adopt(_ document: WidgetDocument?)
}

extension WidgetStateController: WidgetSyncing {}

/// What a widget's views receive: the host, the theme, its descriptor, and
/// access to its documents.
@MainActor
public final class WidgetContext: ObservableObject {
    public let host: FavWidgetHost
    public let theme: WidgetTheme
    public let descriptor: FavWidgetDescriptor
    public let calendar: Calendar
    let cache: WidgetStateCache

    /// Set by the tab so a card's primary action can open the full screen.
    public var openFullView: () -> Void = {}
    /// Set by the tab so a full view can close itself (after Send, etc.).
    public var closeFullView: () -> Void = {}

    public init(host: FavWidgetHost, theme: WidgetTheme, descriptor: FavWidgetDescriptor, cache: WidgetStateCache, calendar: Calendar = .current) {
        self.host = host
        self.theme = theme
        self.descriptor = descriptor
        self.cache = cache
        self.calendar = calendar
    }

    /// The widget's settings/single document.
    public func state<M: WidgetModel>(_ type: M.Type) -> WidgetStateController<M> {
        cache.controller(type, documentId: descriptor.id, schemaVersion: descriptor.schemaVersion)
    }

    /// One month's shard of a monthly widget.
    public func month<M: WidgetModel>(_ type: M.Type, _ month: MonthKey) -> WidgetStateController<M> {
        cache.controller(type, documentId: WidgetShardPlanner.shardId(widgetId: descriptor.id, month: month), schemaVersion: descriptor.schemaVersion)
    }

    public var accent: Color { Color(hex: descriptor.accentHex) }

    public func track(_ name: String, _ parameters: [String: String] = [:]) {
        var params = parameters
        params["widget_id"] = descriptor.id
        host.track(WidgetAnalyticsEvent(name, params))
    }

    public var today: DayKey { DayKey(Date(), calendar: calendar) }
    public var currentMonth: MonthKey { MonthKey(Date(), calendar: calendar) }
}

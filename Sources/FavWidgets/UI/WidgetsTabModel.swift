import SwiftUI
import FavWidgetsCore

/// Drives the tab: preferences, ordering, the batch preload, and the
/// per-widget contexts. One per signed-in user.
@MainActor
public final class WidgetsTabModel: ObservableObject {
    public let host: FavWidgetHost
    public let theme: WidgetTheme
    public let widgets: [any FavWidget]
    public let cache: WidgetStateCache
    public let prefs: WidgetStateController<WidgetPreferences>

    @Published public private(set) var visible: [FavWidgetDescriptor] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?
    @Published public private(set) var hasLoaded = false

    /// The app sets this to push a full view.
    public var onOpen: (any FavWidget, WidgetContext) -> Void = { _, _ in }
    /// The app sets this to present Manage.
    public var onManage: () -> Void = {}

    private var contexts: [String: WidgetContext] = [:]
    private let calendar: Calendar

    /// `widgets` defaults to the registry (resolved here, not in the default
    /// argument, because the registry is main-actor isolated).
    public init(host: FavWidgetHost, theme: WidgetTheme = .default, widgets: [any FavWidget]? = nil, calendar: Calendar = .current) {
        self.host = host
        self.theme = theme
        self.widgets = widgets ?? FavWidgetRegistry.all
        self.calendar = calendar
        self.cache = WidgetStateCache(store: host.dataStore)
        self.prefs = cache.controller(WidgetPreferences.self, documentId: WidgetPreferences.documentId, schemaVersion: WidgetPreferences.schemaVersion)
        recomputeVisible()
    }

    public var descriptors: [FavWidgetDescriptor] { widgets.map(\.descriptor) }

    public func context(for descriptor: FavWidgetDescriptor) -> WidgetContext {
        if let existing = contexts[descriptor.id] { return existing }
        let context = WidgetContext(host: host, theme: theme, descriptor: descriptor, cache: cache, calendar: calendar)
        context.openFullView = { [weak self] in
            guard let self, let widget = self.widgets.first(where: { $0.descriptor.id == descriptor.id }) else { return }
            self.onOpen(widget, context)
        }
        contexts[descriptor.id] = context
        return context
    }

    public func widget(for descriptor: FavWidgetDescriptor) -> (any FavWidget)? {
        widgets.first { $0.descriptor.id == descriptor.id }
    }

    // MARK: - Loading

    /// Paints from cache instantly, then one batch fetch of the hot set.
    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    public func load() async {
        isLoading = !hasLoaded
        loadError = nil
        let ids = WidgetShardPlanner.hotIds(for: descriptors, now: Date(), calendar: calendar)
        if let cached = host.dataStore as? CachedWidgetDataStore {
            adopt(cached.cached(ids: ids))
        }
        do {
            let documents = try await host.dataStore.load(ids: ids)
            adopt(documents)
            markLoaded(ids)
        } catch {
            if !hasLoaded { loadError = "Couldn't load your widgets — pull to refresh" }
            markLoaded(ids)
        }
        hasLoaded = true
        isLoading = false
        recomputeVisible()
    }

    public func refreshAll() async {
        loadError = nil
        let ids = WidgetShardPlanner.hotIds(for: descriptors, now: Date(), calendar: calendar)
        do {
            adopt(try await host.dataStore.load(ids: ids))
        } catch {
            loadError = "Couldn't refresh — check your connection"
        }
        recomputeVisible()
    }

    public func flushAll() async {
        for controller in cache.all { await controller.flush() }
    }

    private func adopt(_ documents: [String: WidgetDocument]) {
        prefs.adopt(documents[WidgetPreferences.documentId])
        for descriptor in descriptors {
            for id in WidgetShardPlanner.hotIds(for: descriptor, now: Date(), calendar: calendar) {
                guard let controller = cache.all.first(where: { $0.documentId == id }) else { continue }
                controller.adopt(documents[id])
            }
        }
        for controller in cache.all where documents[controller.documentId] != nil {
            controller.adopt(documents[controller.documentId])
        }
        recomputeVisible()
    }

    /// Controllers created after the batch landed would refetch on their
    /// own; marking the batch's ids loaded (with nil) keeps that to one
    /// round-trip per open.
    private func markLoaded(_ ids: [String]) {
        for controller in cache.all where ids.contains(controller.documentId) {
            controller.adopt(nil)
        }
    }

    // MARK: - Preferences

    public func recomputeVisible() {
        visible = WidgetOrdering.visible(prefs: prefs.model, descriptors: descriptors)
    }

    public var ordered: [FavWidgetDescriptor] {
        WidgetOrdering.all(prefs: prefs.model, descriptors: descriptors)
    }

    public func setEnabled(_ enabled: Bool, id: String) {
        prefs.update { $0.setEnabled(enabled, id: id) }
        host.track(WidgetAnalyticsEvent("widget_toggled", ["widget_id": id, "enabled": enabled ? "1" : "0"]))
        recomputeVisible()
    }

    public func move(from source: IndexSet, to destination: Int) {
        var ids = ordered.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        prefs.update { $0.order = ids }
        recomputeVisible()
    }

    /// Reorder from the tab itself, where offsets refer to `visible`.
    public func moveVisible(from source: IndexSet, to destination: Int) {
        let next = WidgetOrdering.movingVisible(all: ordered.map(\.id), visibleIds: visible.map(\.id),
                                                fromOffsets: source, toOffset: destination)
        prefs.update { $0.order = next }
        host.track(WidgetAnalyticsEvent("widget_reordered", [:]))
        recomputeVisible()
    }

    public func hasSeenHint(_ key: String) -> Bool { prefs.model.seenHints.contains(key) }

    public func markHintSeen(_ key: String) {
        prefs.update { $0.seenHints.insert(key) }
    }
}

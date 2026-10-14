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
    /// The disk cache painted at least one card: no spinner over them
    @Published public private(set) var hasCachedContent = false
    /// The spinner is only for a first open with nothing cached
    public var showsLoadingSpinner: Bool { isLoading && !hasLoaded && !hasCachedContent }
    /// Whether the Widgets tab is on screen (the app reports it; the tab is
    /// hidden with isHidden, so SwiftUI's onDisappear never fires)
    public private(set) var isTabVisible = true

    /// Most ids one batch read asks for (the server's limit was 30 when the
    /// tab grew to 41 and every open got a 400 — 2026-10-14)
    public static let batchChunkSize = 30

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

    /// Paints from the disk cache (read off the main thread), then fetches
    /// the hot set of the widgets that are SHOWN, in chunks the server
    /// accepts. Cards that appear meanwhile wait for this instead of
    /// fetching their own documents.
    public func load() async {
        isLoading = !hasLoaded
        loadError = nil
        let cachedStore = host.dataStore as? CachedWidgetDataStore
        if let cachedStore {
            let everyId = WidgetShardPlanner.hotIds(for: descriptors, now: Date(), calendar: calendar)
            let (cached, pending) = await Task.detached(priority: .userInitiated) {
                (cachedStore.cached(ids: everyId), cachedStore.pendingIds(among: everyId))
            }.value
            if !cached.isEmpty { hasCachedContent = true }
            adopt(cached)
            // Edits refused while offline last time go out again now.
            for controller in cache.all where pending.contains(controller.documentId) {
                controller.restorePendingEdit()
            }
            recomputeVisible()
        }

        let ids = shownHotIds()
        let batch = Task { try await self.fetchInChunks(ids) }
        cache.preloadGate = { _ = try? await batch.value }
        do {
            let documents = try await batch.value
            cache.seed(documents, requested: ids)
            adopt(documents)
            markLoaded(ids)
        } catch {
            // Cached cards stay as they are; a card with nothing cached
            // fetches its own document when it appears.
            if !hasCachedContent { loadError = "Couldn't load your widgets — pull to refresh" }
        }
        cache.preloadGate = nil
        hasLoaded = true
        isLoading = false
        recomputeVisible()
    }

    public func refreshAll() async {
        loadError = nil
        let ids = shownHotIds()
        do {
            let documents = try await fetchInChunks(ids)
            cache.seed(documents, requested: ids)
            adopt(documents)
        } catch {
            loadError = "Couldn't refresh — check your connection"
        }
        recomputeVisible()
    }

    /// Preferences plus the documents of widgets that are turned on and
    /// store data (not Weather or Recent Contacts).
    func shownHotIds() -> [String] {
        let shown = WidgetOrdering.visible(prefs: prefs.model, descriptors: descriptors)
        return WidgetShardPlanner.hotIds(for: shown, now: Date(), calendar: calendar)
    }

    /// One request per ≤30 ids, in parallel, merged.
    func fetchInChunks(_ ids: [String]) async throws -> [String: WidgetDocument] {
        let size = Self.batchChunkSize
        guard ids.count > size else { return try await host.dataStore.load(ids: ids) }
        let chunks = stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
        let store = host.dataStore
        return try await withThrowingTaskGroup(of: [String: WidgetDocument].self) { group in
            for chunk in chunks { group.addTask { try await store.load(ids: chunk) } }
            var merged: [String: WidgetDocument] = [:]
            for try await part in group { merged.merge(part) { a, _ in a } }
            return merged
        }
    }

    /// The app reports the tab going on/off screen.
    public func setTabVisible(_ visible: Bool) {
        guard visible != isTabVisible else { return }
        isTabVisible = visible
        NotificationCenter.default.post(name: .favWidgetsTabVisibilityChanged, object: nil, userInfo: ["visible": visible])
    }

    public func flushAll() async {
        for controller in cache.all { await controller.flush() }
    }

    /// Hands each document to its controller (one decode each); the caller
    /// recomputes the visible list once.
    private func adopt(_ documents: [String: WidgetDocument]) {
        guard !documents.isEmpty else { return }
        prefs.adopt(documents[WidgetPreferences.documentId])
        for controller in cache.all where controller.documentId != WidgetPreferences.documentId {
            if let document = documents[controller.documentId] { controller.adopt(document) }
        }
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
        if !enabled { contexts[id]?.clearTransients() }
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

public extension Notification.Name {
    /// The Widgets tab went on or off screen (userInfo["visible"]: Bool).
    static let favWidgetsTabVisibilityChanged = Notification.Name("favWidgetsTabVisibilityChanged")
}

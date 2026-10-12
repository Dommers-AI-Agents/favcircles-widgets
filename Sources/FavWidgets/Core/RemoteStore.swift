import Foundation
import Combine
import FavWidgetsCore

/// The loading plumbing every server-backed widget store carried its own
/// copy of: an in-flight guard, "loaded once" and staleness, the error
/// line. Subclasses keep their own `@Published` fields and pass the fetch.
///
/// Stores live in `context.transient` so the card and the full view share
/// one object and a later visit doesn't refetch what the card has.
@MainActor
open class RemoteStore: ObservableObject {
    @Published public private(set) var isLoading = false
    @Published public var loadError: String?
    public private(set) var loadedAt: Date?

    public init() {}

    public var hasLoaded: Bool { loadedAt != nil }

    /// The fetch in progress. It runs on its own task, so one caller's
    /// screen going away (its `.task` cancelled) can't cancel it for the
    /// others: the Events card started a load, the full view waited on it,
    /// the card left, and the full view showed "cancelled" and no events
    /// (2026-10-12).
    private var inFlight: Task<Void, Never>?

    /// Loads once, unless `staleAfter` seconds have passed since the last
    /// success. Concurrent callers wait for the same load.
    public func loadIfNeeded(staleAfter: TimeInterval? = nil, _ fetch: @escaping @MainActor () async throws -> Void) async {
        if inFlight == nil, let loadedAt {
            guard let staleAfter, Date().timeIntervalSince(loadedAt) >= staleAfter else { return }
        }
        await load(fetch)
    }

    /// Always fetches (pull-to-refresh), or waits for the fetch already
    /// running. Errors land in `loadError`; a cancellation is not one.
    public func load(_ fetch: @escaping @MainActor () async throws -> Void) async {
        if let inFlight { return await inFlight.value }
        isLoading = true
        let task = Task { @MainActor [weak self] in
            do {
                try await fetch()
                self?.loadedAt = Date()
                self?.loadError = nil
            } catch {
                // A cancelled load leaves the last good state alone (and
                // no loadedAt, so the next caller fetches again)
                if let message = WidgetErrorText.message(for: error) { self?.loadError = message }
            }
            self?.isLoading = false
            self?.inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// A write returned fresh state: count it as loaded.
    public func markLoaded() { loadedAt = Date() }
}

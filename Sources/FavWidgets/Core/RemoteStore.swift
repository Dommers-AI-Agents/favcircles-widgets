import Foundation
import Combine

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

    /// Loads once, unless `staleAfter` seconds have passed since the last
    /// success. Concurrent callers share the in-flight load.
    public func loadIfNeeded(staleAfter: TimeInterval? = nil, _ fetch: @MainActor () async throws -> Void) async {
        if isLoading { return }
        if let loadedAt {
            guard let staleAfter, Date().timeIntervalSince(loadedAt) >= staleAfter else { return }
        }
        await load(fetch)
    }

    /// Always fetches (pull-to-refresh). Errors land in `loadError`.
    public func load(_ fetch: @MainActor () async throws -> Void) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await fetch()
            loadedAt = Date()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// A write returned fresh state: count it as loaded.
    public func markLoaded() { loadedAt = Date() }
}

import Foundation

/// Wraps the network store with an on-disk copy per document so the tab
/// paints instantly and works offline.
///
/// Reads go to the network; on failure the cached copy is returned instead.
/// `cached(ids:)` is the synchronous fast path the tab uses to paint before
/// the network answers. Every successful read or write refreshes the cache,
/// and a conflict caches the server's copy.
///
/// A save the network refused (offline, server down) is kept on disk marked
/// pending, so the edit survives the process; `WidgetStateController` finds
/// it through `PendingEditStore` on its next load and retries the save.
public final class CachedWidgetDataStore: WidgetDataStore, PendingEditStore, @unchecked Sendable {
    private let inner: WidgetDataStore
    private let directory: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "favwidgets.cache")

    private struct Envelope: Codable {
        var version: Int
        var payload: Data
        var schemaVersion: Int
        var updatedAt: Date?
        /// The network never accepted this copy; optional so envelopes
        /// written before the flag existed still decode.
        var pending: Bool?
    }

    public init(wrapping inner: WidgetDataStore, directory: URL) {
        self.inner = inner
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - WidgetDataStore

    public func load(ids: [String]) async throws -> [String: WidgetDocument] {
        do {
            let fresh = try await inner.load(ids: ids)
            for (id, document) in fresh { write(document, id: id) }
            return fresh
        } catch {
            let fallback = cached(ids: ids)
            if fallback.isEmpty { throw error }
            return fallback
        }
    }

    public func load(id: String) async throws -> WidgetDocument? {
        do {
            let fresh = try await inner.load(id: id)
            if let fresh { write(fresh, id: id) }
            return fresh
        } catch {
            if let fallback = read(id: id) { return fallback }
            throw error
        }
    }

    public func save(id: String, document: WidgetDocument) async throws -> WidgetDocument {
        do {
            let saved = try await inner.save(id: id, document: document)
            write(saved, id: id)
            return saved
        } catch WidgetDataStoreError.conflict(let server) {
            if let server { write(server, id: id) }
            throw WidgetDataStoreError.conflict(server: server)
        } catch {
            // Keep the refused edit; a relaunch retries it.
            write(document, id: id, pending: true)
            throw error
        }
    }

    // MARK: - PendingEditStore

    public func pendingDocument(id: String) -> WidgetDocument? {
        queue.sync {
            guard let envelope = readEnvelope(id: id), envelope.pending == true else { return nil }
            return document(from: envelope)
        }
    }

    public func pendingIds(among ids: [String]) -> [String] {
        ids.filter { pendingDocument(id: $0) != nil }
    }

    // MARK: - Cache access

    /// Cached copies, no network. Missing ids are absent.
    public func cached(ids: [String]) -> [String: WidgetDocument] {
        var result: [String: WidgetDocument] = [:]
        for id in ids {
            if let document = read(id: id) { result[id] = document }
        }
        return result
    }

    public func clear() {
        queue.sync {
            try? fileManager.removeItem(at: directory)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func fileURL(_ id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func read(id: String) -> WidgetDocument? {
        queue.sync { readEnvelope(id: id).map(document(from:)) }
    }

    /// Call on `queue`.
    private func readEnvelope(id: String) -> Envelope? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data)
    }

    private func document(from envelope: Envelope) -> WidgetDocument {
        WidgetDocument(version: envelope.version, payload: envelope.payload,
                       schemaVersion: envelope.schemaVersion, updatedAt: envelope.updatedAt)
    }

    private func write(_ document: WidgetDocument, id: String, pending: Bool = false) {
        queue.sync {
            let envelope = Envelope(version: document.version, payload: document.payload,
                                    schemaVersion: document.schemaVersion, updatedAt: document.updatedAt,
                                    pending: pending)
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? data.write(to: fileURL(id), options: [.atomic])
        }
    }
}

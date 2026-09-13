import Foundation

/// Dictionary-backed store for tests and previews. Mirrors the server's
/// optimistic-lock rule so the sync logic is exercised for real.
public final class InMemoryWidgetDataStore: WidgetDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var documents: [String: WidgetDocument] = [:]

    /// Test hook: thrown by the next `save` (once) when set.
    public var nextSaveError: WidgetDataStoreError?
    /// Test hook: thrown by every `load` while set.
    public var loadError: WidgetDataStoreError?
    public private(set) var saveCount = 0
    public private(set) var loadCount = 0

    public init(seed: [String: WidgetDocument] = [:]) {
        documents = seed
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    public func load(ids: [String]) async throws -> [String: WidgetDocument] {
        try locked {
            loadCount += 1
            if let loadError { throw loadError }
            return documents.filter { ids.contains($0.key) }
        }
    }

    public func load(id: String) async throws -> WidgetDocument? {
        try locked {
            loadCount += 1
            if let loadError { throw loadError }
            return documents[id]
        }
    }

    public func save(id: String, document: WidgetDocument) async throws -> WidgetDocument {
        try locked {
            saveCount += 1
            if let error = nextSaveError {
                nextSaveError = nil
                throw error
            }
            let storedVersion = documents[id]?.version ?? 0
            guard storedVersion == document.version else {
                throw WidgetDataStoreError.conflict(server: documents[id])
            }
            var saved = document
            saved.version = storedVersion + 1
            saved.updatedAt = Date()
            documents[id] = saved
            return saved
        }
    }

    /// Test hook: simulate another device writing.
    public func overwrite(id: String, payload: Data, schemaVersion: Int = 1) {
        locked {
        let next = (documents[id]?.version ?? 0) + 1
        documents[id] = WidgetDocument(version: next, payload: payload, schemaVersion: schemaVersion, updatedAt: Date())
        }
    }

    public func document(id: String) -> WidgetDocument? {
        locked { documents[id] }
    }
}

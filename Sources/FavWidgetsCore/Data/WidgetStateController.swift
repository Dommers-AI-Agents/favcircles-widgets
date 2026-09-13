import Foundation
import Combine

public enum WidgetSyncState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case error(String)
    /// Two devices edited the same document and the automatic merge was
    /// rejected a second time; the local copy is kept until the next edit.
    case conflict
}

/// Owns one document's in-memory model and keeps it synced with the store.
///
/// - Loads once; `reload()` forces a refetch.
/// - `update` applies the change immediately (optimistic) and saves after a
///   short debounce, so tapping "+ Cup" five times is one PUT.
/// - On a version conflict the server copy is merged in via
///   `Model.merge(local:remote:)`, the server version adopted, and the save
///   retried once.
/// - Never discards data: an oversized payload surfaces as `.error`.
@MainActor
public final class WidgetStateController<Model: WidgetModel>: ObservableObject {
    @Published public private(set) var model: Model
    @Published public private(set) var syncState: WidgetSyncState = .idle
    @Published public private(set) var hasLoaded = false

    public let documentId: String
    public let schemaVersion: Int

    private let store: WidgetDataStore
    private let debounce: Duration
    private(set) var version = 0
    private var isDirty = false
    private var saveTask: Task<Void, Never>?
    private var inFlightSave: Task<Void, Never>?
    private var retriedAfterConflict = false

    public init(
        documentId: String,
        schemaVersion: Int,
        store: WidgetDataStore,
        debounce: Duration = .milliseconds(1500)
    ) {
        self.documentId = documentId
        self.schemaVersion = schemaVersion
        self.store = store
        self.debounce = debounce
        self.model = .empty
    }

    // MARK: - Loading

    /// Loads once. Safe to call from every appearance.
    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    /// Refetches from the store. A local unsaved edit is never overwritten:
    /// the server copy is merged into it instead.
    public func reload() async {
        syncState = .loading
        do {
            let document = try await store.load(id: documentId)
            adopt(document)
            if case .loading = syncState { syncState = .idle }
        } catch {
            hasLoaded = true   // an empty model is still usable offline
            syncState = .error(Self.describe(error))
        }
    }

    /// Feeds a document obtained elsewhere (the tab's batch preload, or a
    /// cached copy). Older versions than the one held are ignored.
    public func adopt(_ document: WidgetDocument?) {
        defer { hasLoaded = true }
        guard let document else {
            // Never saved: keep whatever the user has typed locally.
            if !isDirty && version == 0 { model = .empty }
            return
        }
        guard document.version >= version else { return }
        do {
            let remote = try WidgetDocumentCodec.decode(Model.self, from: document.payload)
            model = isDirty ? Model.merge(local: model, remote: remote) : remote
            version = document.version
        } catch {
            // Unreadable server data: keep local, don't clobber the server
            // until the user actually changes something.
            syncState = .error("Couldn't read saved data")
        }
    }

    // MARK: - Editing

    /// Optimistic local change + debounced save.
    public func update(_ mutate: (inout Model) -> Void) {
        var copy = model
        mutate(&copy)
        guard copy != model else { return }
        model = copy
        isDirty = true
        retriedAfterConflict = false
        // A fresh edit re-arms saving after an error or conflict.
        if case .idle = syncState {} else if case .saving = syncState {} else { syncState = .idle }
        scheduleSave()
    }

    /// Replaces the model wholesale (used by merges/imports).
    public func replace(with newModel: Model) {
        update { $0 = newModel }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = debounce
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Saves now if anything is pending (tab hide, app background). Edits
    /// that land while a save is in flight go out in a following round; an
    /// error or an unresolved conflict stops the loop until the next edit.
    public func flush() async {
        saveTask?.cancel()
        if let inFlight = inFlightSave {
            await inFlight.value
        }
        while isDirty {
            let task = Task { await self.performSave() }
            inFlightSave = task
            await task.value
            inFlightSave = nil
            guard case .idle = syncState else { break }
        }
    }

    private func performSave() async {
        let snapshot = model
        let payload: Data
        do {
            payload = try WidgetDocumentCodec.encode(snapshot)
        } catch {
            syncState = .error("Couldn't encode data")
            return
        }
        guard payload.count <= WidgetDocumentLimits.maxPayloadBytes else {
            syncState = .error("This month's log is too large to sync")
            return
        }

        syncState = .saving
        isDirty = false
        let outgoing = WidgetDocument(version: version, payload: payload, schemaVersion: schemaVersion)
        do {
            let saved = try await store.save(id: documentId, document: outgoing)
            version = saved.version
            retriedAfterConflict = false
            if case .saving = syncState { syncState = .idle }
        } catch WidgetDataStoreError.conflict(let server) {
            await resolveConflict(server: server, local: snapshot)
        } catch {
            isDirty = true   // keep it pending for the next flush
            syncState = .error(Self.describe(error))
        }
    }

    private func resolveConflict(server: WidgetDocument?, local: Model) async {
        var serverDocument = server
        if serverDocument == nil {
            serverDocument = try? await store.load(id: documentId)
        }
        guard let serverDocument,
              let remote = try? WidgetDocumentCodec.decode(Model.self, from: serverDocument.payload) else {
            isDirty = true
            syncState = .conflict
            return
        }
        // Merge the server copy under whatever the user has done since.
        let merged = Model.merge(local: model, remote: remote)
        model = merged
        version = serverDocument.version
        isDirty = true
        if retriedAfterConflict {
            syncState = .conflict
            return
        }
        retriedAfterConflict = true
        await performSave()
    }

    private static func describe(_ error: Error) -> String {
        if let storeError = error as? WidgetDataStoreError {
            switch storeError {
            case .unauthorized: return "Sign in to sync"
            case .payloadTooLarge: return "Too much data to sync"
            case .network(let message): return message.isEmpty ? "Couldn't reach FavCircles" : message
            case .decoding(let message): return message
            case .notFound: return "Not found"
            case .conflict: return "Updated on another device"
            }
        }
        return "Couldn't sync"
    }
}

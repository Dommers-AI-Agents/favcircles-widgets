import Foundation

/// One stored document: an opaque JSON payload plus the server's version
/// counter. `version == 0` means "never saved".
public struct WidgetDocument: Equatable, Sendable {
    public var version: Int
    /// JSON-encoded model (the UTF-8 bytes of the wire string).
    public var payload: Data
    public var schemaVersion: Int
    public var updatedAt: Date?

    public init(version: Int, payload: Data, schemaVersion: Int, updatedAt: Date? = nil) {
        self.version = version
        self.payload = payload
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
    }
}

public enum WidgetDataStoreError: Error, Equatable {
    /// The server has a newer version; `server` is its current document
    /// when the API returned one.
    case conflict(server: WidgetDocument?)
    case notFound
    case unauthorized
    case payloadTooLarge(bytes: Int)
    case network(String)
    case decoding(String)
    /// The server refused the document because this build's schema is
    /// older than what is stored; only an app update can sync it.
    case schemaTooOld
}

/// A store that keeps an edit the network refused, so the controller can
/// pick it up again after a relaunch instead of losing it with the process.
public protocol PendingEditStore: AnyObject {
    func pendingDocument(id: String) -> WidgetDocument?
}

/// The persistence contract the app implements (backend-synced) and the
/// package fakes in tests. Document ids are widget ids or month shards
/// (`calories`, `calories_2026-09`, `prefs`).
public protocol WidgetDataStore: AnyObject {
    /// Batch read of the "hot set" at tab open — one round-trip.
    /// Missing documents are simply absent from the result.
    func load(ids: [String]) async throws -> [String: WidgetDocument]
    /// nil when the document has never been saved.
    func load(id: String) async throws -> WidgetDocument?
    /// Sends `document.version` as the expected version; returns the stored
    /// document carrying the new version.
    func save(id: String, document: WidgetDocument) async throws -> WidgetDocument
}

/// Largest payload the package will send. The server caps at 200 KB; the
/// margin leaves room for its own metadata. Data is never dropped to fit —
/// a widget that outgrows a document shards by month instead.
public enum WidgetDocumentLimits {
    public static let maxPayloadBytes = 190 * 1024
}

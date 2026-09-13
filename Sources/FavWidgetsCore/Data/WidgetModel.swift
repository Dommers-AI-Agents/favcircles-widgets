import Foundation

/// A widget's persisted state. Every model has an empty value (what a new
/// user starts with) and a merge rule for the rare two-device conflict.
public protocol WidgetModel: Codable, Equatable {
    static var empty: Self { get }
    /// Called when a save is rejected because another device saved first.
    /// Default: keep the local edit (last write wins). Widgets whose data is
    /// additive (water, habits) override this to union both sides.
    static func merge(local: Self, remote: Self) -> Self
}

public extension WidgetModel {
    static func merge(local: Self, remote: Self) -> Self { local }
}

/// JSON encoding shared by every document so the bytes are stable and
/// diff-friendly (sorted keys, ISO-8601 dates).
public enum WidgetDocumentCodec {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode<M: WidgetModel>(_ model: M) throws -> Data {
        try encoder.encode(model)
    }

    public static func decode<M: WidgetModel>(_ type: M.Type, from data: Data) throws -> M {
        try decoder.decode(type, from: data)
    }
}

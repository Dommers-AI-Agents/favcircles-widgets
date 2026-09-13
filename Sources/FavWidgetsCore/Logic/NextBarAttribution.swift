import Foundation

/// "who saved this" copy shared by the card, the pool list and rounds.
public enum NextBarAttribution {
    /// ["You"] → "on your list"; ["You", "Ana"] → "you + Ana";
    /// ["Ana", "Joe"] → "saved by Ana, Joe"; more than three others → "+N".
    public static func text(savers: [String], fallbackSource: WidgetPlaceSource, fallbackName: String? = nil) -> String {
        var names = savers
        let isMine = names.first == "You"
        if isMine { names.removeFirst() }
        if names.isEmpty {
            if isMine { return "on your list" }
            switch fallbackSource {
            case .mine: return "on your list"
            case .connection: return fallbackName.map { "saved by \($0)" } ?? "saved by a connection"
            case .following: return fallbackName.map { "via \($0)" } ?? "from someone you follow"
            }
        }
        let shown = names.prefix(3).joined(separator: ", ")
        let extra = names.count > 3 ? " +\(names.count - 3)" : ""
        return isMine ? "you + \(shown)\(extra)" : "saved by \(shown)\(extra)"
    }
}

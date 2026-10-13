import Foundation

/// The run screen's line about who knows you're running (2026-10-13: a
/// lost reply meant nobody was told and the runner never knew). Pure.
public enum RunFollowersCopy {
    /// "Brittany", "Brittany and Amanda", "Brittany, Amanda and Joseph",
    /// "Brittany, Amanda and 2 others"
    public static func names(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]) and \(names[2])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }

    /// nil when there's nothing to say (no followers chosen)
    public static func status(waiting: [String], told: [String], noSignal: Bool) -> String? {
        if !waiting.isEmpty {
            return noSignal
                ? "📵 No signal · we'll tell \(names(waiting)) when you're back"
                : "📣 Telling \(names(waiting))…"
        }
        if !told.isEmpty {
            return "👀 \(names(told)) \(told.count == 1 ? "knows" : "know") you're running"
        }
        return nil
    }
}

import Foundation

/// How a 0–10 How Are You? answer reads at a glance (Wes, 2026-11-02):
/// a traffic light. 0–2 red, 3–6 yellow, 7–10 green. Every scale question
/// in the widget is "higher is better" (sleep, mood, energy).
public enum CareScoreBand: Equatable, Sendable {
    case low, middle, good

    public static func band(for score: Int) -> CareScoreBand {
        if score <= 2 { return .low }
        if score <= 6 { return .middle }
        return .good
    }
}

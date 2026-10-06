import Foundation

/// The words around Coach Mane's line in a reminder: a title that shouts
/// and a subtitle that puts the streak on the line (Wes, 2026-10-06: make
/// the push feel more motivating than the words alone).
public enum MotivationNotificationCopy {
    public static let title = "Coach Mane 📣"

    public static func subtitle(streak: Int) -> String {
        switch streak {
        case ...0: return "Day 1 starts now. Move."
        case 1: return "🔥 1 day down. Don't you stop now."
        default: return "🔥 \(streak)-day streak on the line"
        }
    }
}

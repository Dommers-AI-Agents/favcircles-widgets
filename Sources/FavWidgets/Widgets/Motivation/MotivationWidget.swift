import SwiftUI
import FavWidgetsCore

/// Coach Mane yells at you to go train: a line on the card, a shouting coach
/// in the full view, and reminders through the day. Tough love by default;
/// Savage (ruder, still no swearing) is opt-in. Single document (`MotivationLog`).
public struct MotivationWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "motivation",
        title: "Motivation",
        subtitle: "A coach who won't let you skip",
        symbolName: "megaphone.fill",
        accentHex: "#E53E3E",
        category: .fitness,
        storage: .single,
        schemaVersion: MotivationLog.schemaVersion,
        shareBlurb: "A coach who yells at you to get to the gym — as hard as you want."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(MotivationCardView(context: context, state: context.state(MotivationLog.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(MotivationFullView(context: context, state: context.state(MotivationLog.self)))
    }
}

extension MotivationLog {
    /// The line shown on screen right now: changes every hour, and when
    /// "Hit me again" bumps `extra`.
    func currentLine(now: Date = Date(), extra: Int = 0) -> String {
        let pool = MotivationLines.pool(intensity: intensity, focus: focus)
        let hours = Int(now.timeIntervalSince1970 / 3600)
        return MotivationLines.line(pool: pool, day: hours / 24, slot: hours % 24 + extra, slotsPerDay: 24)
    }
}

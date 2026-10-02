import Foundation

/// The coach's lines. Clean never swears; Savage does, on purpose, because
/// the user picked it. No slurs in either bank.
public enum MotivationLines {
    public static func bank(_ intensity: MotivationIntensity, _ focus: MotivationFocus) -> [String] {
        switch (intensity, focus) {
        case (.clean, .gym):
            return [
                "The weights don't lift themselves. Get to the gym.",
                "You're not tired. You're comfortable. Go train.",
                "Nobody ever regretted a workout. Go.",
                "Your couch has had enough of you today. Gym. Now.",
                "Future you is watching. Don't let them down. Lift.",
                "Thirty minutes. That's all. Stop negotiating and go.",
                "Bags packed? Shoes on? Then why are you still reading this?",
                "Soreness is temporary. Quitting lasts. Get under the bar."
            ]
        case (.clean, .run):
            return [
                "Lace up. The road isn't going to run itself.",
                "One mile. Just start. The rest takes care of itself.",
                "Rain, cold, tired — the run doesn't care. Go.",
                "Your legs work. Use them. Go run.",
                "Slow miles still beat no miles. Out the door.",
                "Stop checking the weather. Start checking your pace."
            ]
        case (.clean, .discipline):
            return [
                "Losers make excuses. Winners make time.",
                "Nobody is coming to save you. Get up.",
                "Motivation fades. Discipline shows up anyway. Show up.",
                "You said you would. So do it.",
                "Excuses don't burn calories.",
                "Hard now, easy later. Easy now, hard later. Pick one.",
                "Stop waiting for Monday. It's today.",
                "Do it tired. Do it sore. Just do it."
            ]
        case (.savage, .gym):
            return [
                "Go to the fucking gym, you pussy.",
                "Get your lazy ass off the couch and lift something heavy.",
                "The bar's not going to curl itself, princess. Move.",
                "You skipped yesterday. Skip today and you're a fucking quitter.",
                "Quit scrolling and go lift, you soft little bitch.",
                "Your muscles are crying. From neglect. Go to the damn gym.",
                "Nobody gives a shit how tired you are. Train.",
                "Stop being a pussy and go squat."
            ]
        case (.savage, .run):
            return [
                "Go run, you lazy piece of shit.",
                "Your excuses are slower than you are. Get the fuck out the door.",
                "Lace up, buttercup. Crying is cardio too, but running burns more.",
                "Rain? Who gives a fuck. Run.",
                "Stop being a pussy about the cold. Go run.",
                "Move your ass. The miles won't do themselves."
            ]
        case (.savage, .discipline):
            return [
                "Losers make excuses. Are you a fucking loser?",
                "Nobody's coming to save your sorry ass. Get up.",
                "Quit bitching and do the work.",
                "Your excuses are bullshit and you know it.",
                "Stop being soft. Do the damn thing.",
                "Motivation is for pussies. Discipline. Now.",
                "You said you'd do it. Don't be a lying little bitch. Go.",
                "Get off your ass. Today. Not tomorrow. Today."
            ]
        }
    }

    /// Every line for the chosen intensity and focus areas. No focus picked
    /// means all of them.
    public static func pool(intensity: MotivationIntensity, focus: [MotivationFocus]) -> [String] {
        let areas = focus.isEmpty ? MotivationFocus.allCases : MotivationFocus.allCases.filter(focus.contains)
        return areas.flatMap { bank(intensity, $0) }
    }

    /// Deterministic pick for slot `slot` on `day` (days since 1970). Walks
    /// the pool with a stride coprime to its size so consecutive slots and
    /// consecutive days don't repeat until the pool is used up.
    public static func line(pool: [String], day: Int, slot: Int, slotsPerDay: Int) -> String {
        guard !pool.isEmpty else { return "Get moving." }
        let n = pool.count
        let sequence = day * max(1, slotsPerDay) + slot
        var stride = 7
        while gcd(stride, n) != 1 { stride += 1 }
        let index = ((sequence % n + n) % n * stride) % n
        return pool[index]
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

/// Which notifications to schedule. Repeating triggers carry fixed text, so
/// instead the next few days are scheduled one by one, each with its own
/// line, and re-planned whenever the widget opens or a setting changes.
public enum MotivationPlan {
    public struct Slot: Equatable, Sendable {
        public let day: DayKey
        public let minutes: Int
        public let line: String
    }

    /// Stays well under iOS's 64 pending local notifications.
    public static let maxPending = 56

    public static func slots(
        _ log: MotivationLog,
        now: Date,
        quietHours: WidgetQuietHours? = nil,
        calendar: Calendar = .current
    ) -> [Slot] {
        guard log.reminders.enabled else { return [] }
        let times = WaterReminderPlan.times(log.reminders, quietHours: quietHours)
        guard !times.isEmpty else { return [] }
        let days = max(1, min(7, maxPending / times.count))
        let pool = MotivationLines.pool(intensity: log.intensity, focus: log.focus)
        let today = DayKey(now, calendar: calendar)
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        var out: [Slot] = []
        for offset in 0..<days {
            let day = today.adding(days: offset, calendar: calendar)
            // Already went today: the coach leaves you alone until tomorrow.
            if offset == 0, log.isDone(day) { continue }
            let dayNumber = Int(day.date(calendar: calendar).timeIntervalSince1970 / 86_400)
            for (slot, minutes) in times.enumerated() {
                if offset == 0, minutes <= nowMinutes { continue }
                out.append(Slot(day: day, minutes: minutes,
                                line: MotivationLines.line(pool: pool, day: dayNumber, slot: slot, slotsPerDay: times.count)))
            }
        }
        return Array(out.prefix(maxPending))
    }
}

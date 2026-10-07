import Foundation

/// The coach's lines. Neither bank swears (Wes 2026-10-02: keep the app off
/// the profanity age rating); Savage is just ruder. Opt-in, because
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
                "Soreness is temporary. Quitting lasts. Get under the bar.",
                "Warm up, show up, finish up. That's the whole plan.",
                "The hardest lift is getting out the door. You've got this one.",
                "Strong is built one boring rep at a time. Go collect some.",
                "You don't need a perfect workout. You need today's workout."
            ]
        case (.clean, .run):
            return [
                "Lace up. The road isn't going to run itself.",
                "One mile. Just start. The rest takes care of itself.",
                "Rain, cold, tired — the run doesn't care. Go.",
                "Your legs work. Use them. Go run.",
                "Slow miles still beat no miles. Out the door.",
                "Stop checking the weather. Start checking your pace.",
                "Two minutes in, you'll be glad you went. Go find out.",
                "Easy pace still counts. Out the door.",
                "The best runners started as people who just kept showing up.",
                "Fresh air, clear head, better day. Go run.",
                "Shoes on is half the battle. Win the other half."
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
                "Do it tired. Do it sore. Just do it.",
                "Small promises kept make big results. Keep one today.",
                "You don't have to feel like it. You just have to do it.",
                "Do the hard thing first. The rest of the day gets easier.",
                "Progress, not perfection. Go make some."
            ]
        // Legends: Coach Mane quoting real champions. Only lines widely
        // attributed to them; the rest is the coach talking.
        case (.clean, .legends):
            return [
                "Muhammad Ali: “Don't quit. Suffer now and live the rest of your life as a champion.” Champ's orders.",
                "Ali didn't count his sit-ups until they started hurting. That's when they count. Go.",
                "Michael Jordan: “I've failed over and over and over again in my life. And that is why I succeed.” Go fail forward.",
                "Wayne Gretzky: “You miss 100% of the shots you don't take.” Take the shot. Go train.",
                "Steve Prefontaine: “To give anything less than your best is to sacrifice the gift.” Don't waste yours.",
                "Eliud Kipchoge: “No human is limited.” That includes you. Lace up.",
                "Babe Ruth: “It's hard to beat a person who never gives up.” Be that person today.",
                "Billie Jean King: “Champions keep playing until they get it right.” Keep playing.",
                "David Goggins: “Who's gonna carry the boats?” You are. Go.",
                "Every champion you admire had a day they didn't feel like it. They went anyway. Your turn."
            ]
        case (.savage, .legends):
            return [
                "Ali said: “Suffer now and live the rest of your life as a champion.” You picked suffer later. Bad trade.",
                "Ali only started counting sit-ups when they hurt. You stop when they hurt. See the problem?",
                "Jordan failed over and over and kept going. You failed once and took a nap.",
                "Gretzky: “You miss 100% of the shots you don't take.” You haven't taken one all week.",
                "Prefontaine said anything less than your best sacrifices the gift. You're returning yours unopened.",
                "Kipchoge says no human is limited. You found a way anyway. Prove him right instead.",
                "Babe Ruth said it's hard to beat a person who never gives up. You're easy to beat. Fix that.",
                "Billie Jean King said champions keep playing until they get it right. You quit before you got it wrong.",
                "Goggins wants to know who's gonna carry the boats. Not you, apparently. Get up.",
                "Rocky got knocked down and got back up. You got comfortable and stayed down. Up."
            ]
        case (.savage, .gym):
            return [
                "Get to the gym. Right now. Move it.",
                "Off the couch, lazybones. Lift something heavy.",
                "The bar's not going to curl itself, princess. Move.",
                "You skipped yesterday. Skip today and you're a quitter.",
                "Put the phone down and go lift, softie.",
                "Your muscles are crying. From neglect. Go train.",
                "Nobody cares how tired you are. Train.",
                "Stop being so soft and go squat.",
                "Your gym membership is the most expensive thing you never use.",
                "The weights miss you. Nobody else does. Go see them.",
                "You lift your phone more than you lift anything else. Pathetic.",
                "Leg day called. You let it go to voicemail again, coward.",
                "Even your shadow is embarrassed to follow you around.",
                "Your warm-up is everyone else's whole workout. Do better.",
                "The dumbbells are lighter than your excuses. Pick one up.",
                "Your gym bag has been packed for a week. It's ashamed of you.",
                "Somewhere a 70-year-old is out-lifting you right now. Think about that.",
                "You're not resting. You're rotting. Get under the bar.",
                "Your bench press is a rumor. Go prove it exists.",
                "Sore? Good. Means you finally did something. Go again.",
                "You talk about gains like you've ever met one.",
                "The squat rack has a waitlist. You're not even on it.",
                "Your biceps filed a missing persons report. Go find them.",
                "Cute plan. Shame you never follow it. Gym. Now.",
                "You've been 'starting Monday' for three years.",
                "The treadmill has more mileage on it from strangers than from you.",
                "You're one more skipped session away from being a cautionary tale.",
                "Your excuses do more reps than you do.",
                "You don't need a better playlist. You need a spine.",
                "The iron doesn't care about your feelings. Neither do I. Lift.",
                "Your protein shaker has never seen a workout. Neither have you lately.",
                "Weak today, weak tomorrow, unless you get up. Your call.",
                "Stop admiring other people's progress. Make some of your own.",
                "You flinch at a 20-pound plate. Unbelievable. Go fix that.",
                "Your rest days have rest days. Enough."
            ]
        case (.savage, .run):
            return [
                "Go run, you lazy couch potato.",
                "Your excuses are slower than you are. Out the door. Now.",
                "Lace up, buttercup. Crying is cardio too, but running burns more.",
                "Rain? Who cares. Run.",
                "Quit whining about the cold. Go run.",
                "Move it. The miles won't run themselves.",
                "Your running shoes still have the store smell. Disgraceful.",
                "A turtle just lapped you. From its couch.",
                "You get winded climbing stairs. Fix it. Go run.",
                "Your fastest mile was to the fridge.",
                "The road is free. Your laziness is costing you everything.",
                "Snails have better cardio than you. Prove me wrong.",
                "Every step you skip, someone faster takes.",
                "You're not built for speed. You're built for snacks. Change that.",
                "Your Strava is a ghost town. Go haunt it.",
                "Too hot, too cold, too tired. You're too predictable. Run.",
                "You chase the ice cream truck harder than your goals.",
                "Your lungs are on vacation. Cancel it.",
                "A mile won't kill you. Your couch might.",
                "Run like your excuses are chasing you. Because they are.",
                "You call that a jog? I've seen faster glaciers.",
                "Your running watch thinks you died. Go reassure it.",
                "The finish line doesn't come to you, genius.",
                "Stop stretching for twenty minutes to avoid running for ten.",
                "You're out of breath reading this. That's the problem.",
                "Pace yourself? You'd have to start first.",
                "Weather's perfect for a quitter. Don't be one. Run.",
                "Your legs work fine. Your willpower is what's broken.",
                "Get out there before the sun sees you being lazy.",
                "Slow is fine. Stopped is pathetic. Move."
            ]
        case (.savage, .discipline):
            return [
                "Losers make excuses. Are you a loser?",
                "Nobody's coming to save you. Get up.",
                "Quit complaining and do the work.",
                "Your excuses are garbage and you know it.",
                "Stop being soft. Do the thing.",
                "Motivation is overrated. Discipline. Now.",
                "You said you'd do it. Don't be a liar. Go.",
                "Get up. Today. Not tomorrow. Today.",
                "You're not tired. You're undisciplined.",
                "Your comfort zone is a cage you built yourself. Get out.",
                "Winners are training while you're reading notifications.",
                "You quit so often you should put it on your resume.",
                "Your potential is wasted on you.",
                "You keep waiting to feel ready. Ready isn't coming. Go.",
                "Talk is cheap. Yours is free. Do something.",
                "The version of you that you brag about doesn't exist yet.",
                "Your goals are fiction until you move.",
                "Lazy is a choice. Stop choosing it.",
                "Nobody remembers people who almost did it.",
                "You've got a black belt in procrastination. Congratulations, I guess.",
                "Average is a crowded place. You fit right in. Leave.",
                "Your future self is already disappointed. Prove them wrong.",
                "You don't have a time problem. You have a priorities problem.",
                "Sitting there won't make you better. It never has.",
                "Some people chase dreams. You hit snooze on yours.",
                "Stop scrolling through other people's lives and fix your own.",
                "You're a professional at starting over. Try finishing.",
                "Your couch has a permanent imprint of you. Embarrassing.",
                "Tough times don't last. Soft people don't either.",
                "The only thing you're consistent at is quitting.",
                "If excuses burned calories, you'd be a legend.",
                "Nobody is impressed by plans. Execute.",
                "Your alarm clock has given up on you. Don't give up on yourself.",
                "You want results without effort. That's called dreaming.",
                "Regret weighs more than any dumbbell. Pick your pain."
            ]
        }
    }

    /// Every line for the chosen intensity and focus areas. No focus picked
    /// means all of them.
    public static func pool(intensity: MotivationIntensity, focus: [MotivationFocus]) -> [String] {
        let areas = focus.isEmpty ? MotivationFocus.allCases : MotivationFocus.allCases.filter(focus.contains)
        return areas.flatMap { bank(intensity, $0) }
    }

    /// A stable short id for a line: FNV-1a of its text as 8 hex digits.
    /// Survives reordering the banks and is safe in a deep link (no colons).
    /// Notifications carry it so "Send to someone" opens on the same line.
    public static func id(for line: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in line.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }

    /// Every line in every bank.
    public static var all: [String] {
        MotivationIntensity.allCases.flatMap { pool(intensity: $0, focus: MotivationFocus.allCases) }
    }

    /// The line an id was made from, if it's still in a bank.
    public static func line(id: String) -> String? {
        all.first { Self.id(for: $0) == id }
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

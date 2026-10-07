import Foundation

/// What Coach Mane yells at the end of each mile (or km) of a FavRun
/// (Wes, 2026-10-07): first something about the mile you just ran, then
/// trash talk to keep you going. Pure, so it's tested; the run session speaks it.
public enum CoachRunCalls {
    /// The words spoken after split `index` (0-based) of `splits` (seconds each).
    /// `pick` chooses among options (tests pass a fixed one).
    public static func call(splits: [Double], index: Int, unit: RunUnit, intensity: MotivationIntensity,
                            pick: (Int) -> Int = { Int.random(in: 0..<max($0, 1)) }) -> String {
        guard splits.indices.contains(index) else { return "" }
        let n = index + 1
        let word = unit == .miles ? "mile" : "K"
        let time = spoken(splits[index])
        var about = "\(ordinal(n)) \(word) done. \(time)."
        if index > 0 {
            let delta = splits[index] - splits[index - 1]
            let faster = delta < 0
            if abs(delta) < 5 {
                about += " Same as the last one. Steady."
            } else {
                about += " \(spoken(abs(delta))) \(faster ? "faster" : "slower") than the last one."
            }
        }
        if let best = splits.prefix(index).min(), index > 0, splits[index] < best - 0.5 {
            about += " Fastest \(word) of the run."
        }
        let roast = roasts(for: splits, index: index, unit: unit, intensity: intensity)
        return about + " " + roast[min(max(pick(roast.count), 0), roast.count - 1)]
    }

    /// The trash talk, chosen by how this split went.
    static func roasts(for splits: [Double], index: Int, unit: RunUnit, intensity: MotivationIntensity) -> [String] {
        let slower = index > 0 && splits[index] - splits[index - 1] >= 5
        let faster = index > 0 && splits[index - 1] - splits[index] >= 5
        // 5K / 10K by km; 3 and 6.2 miles don't land on a split, so miles skip it
        if unit == .kilometers && (index == 4 || index == 9) {
            let race = index == 4 ? "5K" : "10K"
            return [intensity == .savage
                ? "That's a \(race). Don't you dare stop and post about it yet. Keep going."
                : "That's a \(race). Strong work. See how far you can take it."]
        }
        switch (intensity, slower, faster) {
        case (.savage, true, _): return slowerSavage
        case (.savage, _, true): return fasterSavage
        case (.savage, _, _): return steadySavage
        case (_, true, _): return slowerClean
        case (_, _, true): return fasterClean
        default: return steadyClean
        }
    }

    /// "8 minutes 12 seconds" / "45 seconds"
    public static func spoken(_ seconds: Double) -> String {
        let t = max(0, Int(seconds.rounded()))
        let m = t / 60, s = t % 60
        if m == 0 { return "\(s) second\(s == 1 ? "" : "s")" }
        if s == 0 { return "\(m) minute\(m == 1 ? "" : "s")" }
        return "\(m) minute\(m == 1 ? "" : "s") \(s)"
    }

    static func ordinal(_ n: Int) -> String {
        let words = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth",
                     "Eleventh", "Twelfth", "Thirteenth", "Fourteenth", "Fifteenth", "Sixteenth", "Seventeenth",
                     "Eighteenth", "Nineteenth", "Twentieth"]
        if n >= 1 && n <= words.count { return words[n - 1] }
        return "Number \(n)"
    }

    static let slowerSavage = [
        "You slowed down. Did you stop to smell the flowers? Pick it up.",
        "That was slower. My grandma walks faster, and she's got a bad hip.",
        "You're fading. The couch can't hear you begging. Move.",
        "Slower? Seriously? Your legs filed a complaint and you accepted it.",
        "That mile was a crime scene. Go faster before someone reports it.",
        "Are you jogging or window shopping? Speed up.",
        "You got slower. The finish line is not going to come pick you up."
    ]
    static let fasterSavage = [
        "Faster. Finally. Don't get cocky, keep it going.",
        "Look at you, almost athletic. Do it again.",
        "That's more like it. Now prove it wasn't a fluke.",
        "Faster mile. I'm shocked. Keep shocking me.",
        "Good. Now stop smiling and hold that pace."
    ]
    static let steadySavage = [
        "Steady is fine. Boring, but fine. Push a little.",
        "Same pace. Great, you're a metronome. Now be a faster one.",
        "You're cruising. Cruising is for boats. Run.",
        "Not bad. Not good either. Give me more.",
        "Your excuses are slower than you are. Keep moving.",
        "A turtle just lapped you. From its couch. Pick it up."
    ]
    static let slowerClean = [
        "You slowed a little. Shake out your arms and pick it back up.",
        "Little slower that time. Short steps, quick feet. You've got this.",
        "Tired is temporary. Find your rhythm and go.",
        "Slower mile. That's okay. The next one is yours."
    ]
    static let fasterClean = [
        "Faster than the last one. That's how it's done.",
        "Nice negative split. Keep that energy.",
        "You're getting stronger as you go. Love it.",
        "Faster mile. Stay relaxed and hold it."
    ]
    static let steadyClean = [
        "Nice and steady. Keep breathing, keep moving.",
        "Good rhythm. Stay tall and keep it rolling.",
        "Locked in. One more, then one more after that.",
        "Solid work. The hard part is starting, and you already did that."
    ]
}

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
                about += " Same as the last one."
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
                ? "That's a \(race). Don't you dare stop now, weakling. Keep going!"
                : "That's a \(race). Strong work. Now go further!"]
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
        "You slowed down, weakling. Did your legs ask for permission to quit? Denied. Move!",
        "Slower? Pathetic. My grandma runs faster carrying groceries. Pick it up!",
        "You're fading. Nobody's coming to carry you. Push!",
        "That mile was soft. I don't coach soft. Faster!",
        "Are you jogging or sightseeing? Speed up, weakling!",
        "You got slower. The finish line doesn't care how tired you are. Neither do I. Go!",
        "Is that all you've got? I've seen toddlers with more fight. Dig in!"
    ]
    static let fasterSavage = [
        "Faster. Finally. Don't you dare get comfortable. Again!",
        "That's more like it. Now prove it wasn't luck. Push!",
        "Good. Now do it again, and harder. No rest!",
        "Faster mile. I'm not impressed yet. Impress me!",
        "There's the beast. Keep him out of the cage. Go!"
    ]
    static let steadySavage = [
        "Same pace? Comfortable is for weaklings. Push harder!",
        "You're cruising. Cruising is for boats. Run!",
        "Not bad. Not good either. Give me more!",
        "Your excuses are slower than you are. Keep moving!",
        "Steady? I don't want steady. I want savage. Pick it up!",
        "You think the road's tired? Run it down!"
    ]
    static let slowerClean = [
        "You slowed down. Shake it off and attack the next one. Go!",
        "Little slower. Short steps, quick feet. Fight for it!",
        "Tired is temporary. Strong is forever. Push!",
        "Slower mile. Doesn't matter. The next one is yours. Take it!"
    ]
    static let fasterClean = [
        "Faster than the last one. That's how a beast runs!",
        "Negative split. Keep hunting!",
        "You're getting stronger. Don't let up now!",
        "Faster mile. Hold it. Own it!"
    ]
    static let steadyClean = [
        "Steady and strong. Now give me a little more!",
        "Good rhythm. Stand tall and drive those legs!",
        "Locked in. One more, then one more after that. Go!",
        "Solid. Champions keep going when it gets hard. Move!"
    ]
}

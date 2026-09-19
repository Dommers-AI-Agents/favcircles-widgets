import Foundation

// Sleep Sounds: ambient noise you mix and fall asleep to. Every sound is
// synthesized on the device (see SleepSoundGenerators), so there is no
// audio to download and nothing ever loops.

/// What a sound is, for the engine.
public enum SleepSoundKind: String, Codable, CaseIterable, Sendable {
    case white, pink, brown
    case rain, thunder, ocean, stream, wind, crickets, fire
    case fan, heartbeat
}

/// One tile in the mixer.
public struct SleepSound: Identifiable, Hashable, Sendable {
    public let kind: SleepSoundKind
    public let name: String
    public let symbolName: String
    public let group: String

    public var id: String { kind.rawValue }

    public init(_ kind: SleepSoundKind, _ name: String, _ symbolName: String, group: String) {
        self.kind = kind
        self.name = name
        self.symbolName = symbolName
        self.group = group
    }
}

public enum SleepSoundCatalog {
    public static let all: [SleepSound] = [
        SleepSound(.rain, "Rain", "cloud.rain.fill", group: "Nature"),
        SleepSound(.thunder, "Thunder", "cloud.bolt.fill", group: "Nature"),
        SleepSound(.ocean, "Ocean", "water.waves", group: "Nature"),
        SleepSound(.stream, "Stream", "drop.fill", group: "Nature"),
        SleepSound(.wind, "Wind", "wind", group: "Nature"),
        SleepSound(.crickets, "Crickets", "moon.stars.fill", group: "Nature"),
        SleepSound(.fire, "Campfire", "flame.fill", group: "Nature"),
        SleepSound(.fan, "Fan", "fanblades.fill", group: "Indoors"),
        SleepSound(.heartbeat, "Heartbeat", "heart.fill", group: "Indoors"),
        SleepSound(.white, "White noise", "waveform", group: "Noise"),
        SleepSound(.pink, "Pink noise", "waveform.path", group: "Noise"),
        SleepSound(.brown, "Brown noise", "waveform.path.ecg", group: "Noise")
    ]

    public static func sound(id: String) -> SleepSound? { all.first { $0.id == id } }
    public static let groups: [String] = ["Nature", "Indoors", "Noise"]
    /// Tiles by group, built once; the mixer grid reads it per row.
    public static let byGroup: [String: [SleepSound]] = Dictionary(grouping: all, by: \.group)
}

/// A named set of levels, 0…1 per sound id. Absent = off.
public struct SleepMix: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var levels: [String: Double]

    public init(id: String = UUID().uuidString, name: String, levels: [String: Double]) {
        self.id = id
        self.name = name
        self.levels = levels
    }

    /// Sounds that are actually audible, loudest first.
    public var activeIds: [String] {
        levels.filter { $0.value > 0.001 }.sorted { $0.value > $1.value }.map(\.key)
    }

    /// "Rain + Thunder" from the levels, for a mix nobody has named.
    public static func describe(levels: [String: Double]) -> String {
        let names = SleepMix(name: "", levels: levels).activeIds.compactMap { SleepSoundCatalog.sound(id: $0)?.name }
        if names.isEmpty { return "Silence" }
        if names.count <= 2 { return names.joined(separator: " + ") }
        return "\(names[0]) + \(names.count - 1) more"
    }

    /// The presets everyone starts with. Ids are stable so a saved
    /// `lastMixId` still resolves after an update.
    public static let builtIns: [SleepMix] = [
        SleepMix(id: "preset_rainy_night", name: "Rainy Night", levels: ["rain": 0.8, "thunder": 0.35]),
        SleepMix(id: "preset_ocean", name: "Ocean Breeze", levels: ["ocean": 0.9, "wind": 0.25]),
        SleepMix(id: "preset_deep", name: "Deep Sleep", levels: ["brown": 0.7, "fan": 0.3]),
        SleepMix(id: "preset_campfire", name: "Campfire", levels: ["fire": 0.8, "crickets": 0.4, "wind": 0.15]),
        SleepMix(id: "preset_forest", name: "Forest Stream", levels: ["stream": 0.75, "crickets": 0.35, "wind": 0.2]),
        SleepMix(id: "preset_womb", name: "Womb", levels: ["heartbeat": 0.6, "pink": 0.45]),
        SleepMix(id: "preset_fan", name: "Just a Fan", levels: ["fan": 0.9])
    ]
}

/// Settings document (one for all time): saved mixes and where the mixer
/// was left, so the card's Play button brings back last night's sound.
public struct SleepSoundsSettings: WidgetModel {
    public var mixes: [SleepMix]
    public var lastLevels: [String: Double]
    public var lastMixName: String?
    public var timerMinutes: Int
    public var masterVolume: Double

    public init(mixes: [SleepMix] = [], lastLevels: [String: Double] = [:], lastMixName: String? = nil,
                timerMinutes: Int = 45, masterVolume: Double = 0.8) {
        self.mixes = mixes
        self.lastLevels = lastLevels
        self.lastMixName = lastMixName
        self.timerMinutes = timerMinutes
        self.masterVolume = masterVolume
    }

    public static let empty = SleepSoundsSettings()

    /// What Play should start with: last night's mix, or the first preset.
    public var startingLevels: [String: Double] {
        lastLevels.values.contains { $0 > 0.001 } ? lastLevels : SleepMix.builtIns[0].levels
    }

    public var startingName: String {
        lastLevels.values.contains { $0 > 0.001 } ? (lastMixName ?? SleepMix.describe(levels: lastLevels)) : SleepMix.builtIns[0].name
    }

    /// Two devices saving mixes: keep both sets, newest settings otherwise.
    public static func merge(local: SleepSoundsSettings, remote: SleepSoundsSettings) -> SleepSoundsSettings {
        var merged = local
        for mix in remote.mixes where !merged.mixes.contains(where: { $0.id == mix.id }) {
            merged.mixes.append(mix)
        }
        return merged
    }
}

/// One night (or nap) of playback. Written when playback stops.
public struct SleepSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var seconds: Int
    public var mixName: String

    public init(id: String = UUID().uuidString, startedAt: Date, seconds: Int, mixName: String) {
        self.id = id
        self.startedAt = startedAt
        self.seconds = seconds
        self.mixName = mixName
    }
}

/// One month's sessions. Never pruned; a year of nightly use is ~40 KB.
public struct SleepSoundsMonth: WidgetModel {
    public var sessions: [SleepSession]

    public init(sessions: [SleepSession] = []) { self.sessions = sessions }

    public static let empty = SleepSoundsMonth()

    /// Distinct calendar days with a session of at least ten minutes.
    public func nights(calendar: Calendar = .current) -> Int {
        Set(sessions.filter { $0.seconds >= 600 }.map { DayKey($0.startedAt, calendar: calendar) }).count
    }

    public var totalSeconds: Int { sessions.reduce(0) { $0 + $1.seconds } }

    public static func merge(local: SleepSoundsMonth, remote: SleepSoundsMonth) -> SleepSoundsMonth {
        var merged = local
        for session in remote.sessions where !merged.sessions.contains(where: { $0.id == session.id }) {
            merged.sessions.append(session)
        }
        merged.sessions.sort { $0.startedAt < $1.startedAt }
        return merged
    }
}

/// Sleep-timer arithmetic, shared by the engine and its tests.
public enum SleepTimer {
    /// Minutes offered in the picker; 0 = play until stopped.
    public static let choices = [0, 15, 30, 45, 60, 90, 120]
    /// The sound eases out over the last minute rather than cutting off.
    public static let fadeSeconds: TimeInterval = 60

    /// Master multiplier for `remaining` seconds left: 1 until the fade
    /// starts, then a smooth curve to 0 (equal-power-ish, no audible step).
    public static func fadeGain(remaining: TimeInterval) -> Float {
        if remaining >= fadeSeconds { return 1 }
        if remaining <= 0 { return 0 }
        let t = remaining / fadeSeconds
        return Float(t * t * (3 - 2 * t))
    }

    /// "32 min", "1 h 05 min", "under a minute".
    public static func remainingText(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded()))
        if seconds < 60 { return "under a minute" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    public static func choiceText(_ minutes: Int) -> String {
        if minutes == 0 { return "Off" }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : String(format: "%dh%02d", minutes / 60, minutes % 60)
    }
}

/// The words on the card and in the full view.
public enum SleepSoundsCopy {
    public static func cardSummary(isPlaying: Bool, mixName: String, remaining: TimeInterval?, nightsThisMonth: Int) -> String {
        if isPlaying {
            if let remaining { return "Playing \(mixName) · \(SleepTimer.remainingText(remaining)) left" }
            return "Playing \(mixName)"
        }
        var parts = [mixName]
        if nightsThisMonth > 0 { parts.append(nightsThisMonth == 1 ? "1 night this month" : "\(nightsThisMonth) nights this month") }
        return parts.joined(separator: " · ")
    }

    public static func monthSummary(nights: Int, totalSeconds: Int) -> String {
        if nights == 0 && totalSeconds < 600 { return "No nights yet. Press play and drift off." }
        let hours = Double(totalSeconds) / 3600
        let n = nights == 1 ? "1 night" : "\(nights) nights"
        return hours < 1 ? "\(n) this month" : String(format: "%@ this month · %.1f hours", n, hours)
    }
}

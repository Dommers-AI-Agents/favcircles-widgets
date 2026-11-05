import Foundation

/// Wake Up (Wes, 2026-11-05): real alarms that ring like the Clock app's,
/// each with a station from Pandora, Spotify, Apple Music or any music app.
/// Stop wakes you and opens that station; Snooze rings again in a few
/// minutes. Settings are one small document, so alarms come back after a
/// reinstall (the phone re-sets them when the widget opens).
public struct AlarmClockSettings: WidgetModel {
    public static let schemaVersion = 1
    public var alarms: [WakeAlarm]
    public var stations: [MusicStation]
    public init(alarms: [WakeAlarm] = [], stations: [MusicStation] = []) {
        self.alarms = alarms; self.stations = stations
    }
    public static let empty = AlarmClockSettings()

    public func station(id: String?) -> MusicStation? {
        guard let id else { return nil }
        return stations.first { $0.id == id }
    }
}

public struct WakeAlarm: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// A UUID string: the phone's alarm uses the same id, so re-setting replaces it
    public var id: String
    /// Minutes after midnight
    public var minutes: Int
    /// 1 = Sunday … 7 = Saturday; empty = rings once
    public var days: [Int]
    public var label: String
    public var stationId: String?
    /// 0 = no Snooze button
    public var snoozeMinutes: Int
    public var enabled: Bool
    /// A one-time alarm's ring, so it can switch itself off afterwards
    public var onceAt: Date?

    public init(id: String = UUID().uuidString, minutes: Int = 7 * 60, days: [Int] = [], label: String = "",
                stationId: String? = nil, snoozeMinutes: Int = AlarmClockPlan.defaultSnooze, enabled: Bool = true,
                onceAt: Date? = nil) {
        self.id = id; self.minutes = minutes; self.days = days.sorted(); self.label = label
        self.stationId = stationId; self.snoozeMinutes = snoozeMinutes; self.enabled = enabled; self.onceAt = onceAt
    }

    public var repeats: Bool { !days.isEmpty }
}

/// A station the person pasted from their music app's Share button.
public struct MusicStation: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var link: String

    public init(id: String = UUID().uuidString, name: String, link: String) {
        self.id = id; self.name = name; self.link = link
    }

    public var url: URL? { MusicLink.url(from: link) }
    public var service: MusicService { MusicLink.service(of: link) }
}

public enum MusicService: String, Codable, Sendable {
    case pandora, spotify, appleMusic, youtubeMusic, amazonMusic, other

    public var name: String {
        switch self {
        case .pandora: return "Pandora"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .youtubeMusic: return "YouTube Music"
        case .amazonMusic: return "Amazon Music"
        case .other: return "Music"
        }
    }

    public var symbolName: String {
        switch self {
        case .pandora: return "dot.radiowaves.left.and.right"
        case .appleMusic: return "music.note"
        case .other: return "link"
        default: return "music.note.list"
        }
    }
}

/// Pasted share links: "pandora.app.link/…", "https://www.pandora.com/station/…",
/// "open.spotify.com/…", "spotify:playlist:…", "music.apple.com/…".
public enum MusicLink {
    /// The link as something to open, or nil when it isn't one. A link
    /// without a scheme gets https; app schemes (pandora:, spotify:) pass.
    public static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A share sheet often adds words around the link: take the link itself
        let candidate = trimmed.split(whereSeparator: { $0.isWhitespace }).first { $0.contains(".") || $0.contains(":") }
            .map(String.init) ?? trimmed
        guard !candidate.isEmpty else { return nil }
        let lower = candidate.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: candidate), let host = url.host, host.contains(".") else { return nil }
            return url
        }
        for scheme in appSchemes where lower.hasPrefix(scheme + ":") {
            return URL(string: candidate)
        }
        guard lower.contains("."), !lower.contains(" "), let url = URL(string: "https://" + candidate),
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    static let appSchemes = ["pandora", "spotify", "music", "youtubemusic"]

    public static func service(of text: String) -> MusicService {
        guard let url = url(from: text) else { return .other }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        if scheme == "pandora" || host.hasSuffix("pandora.com") || host.hasSuffix("pandora.app.link") { return .pandora }
        if scheme == "spotify" || host.hasSuffix("spotify.com") || host == "spotify.link" { return .spotify }
        if scheme == "music" || host == "music.apple.com" { return .appleMusic }
        if scheme == "youtubemusic" || host == "music.youtube.com" { return .youtubeMusic }
        if host == "music.amazon.com" || host.hasSuffix("amazon.com") && url.path.hasPrefix("/music") { return .amazonMusic }
        return .other
    }
}

/// Times, days and "rings in" words for alarms.
public enum AlarmClockPlan {
    public static let defaultSnooze = 9
    public static let snoozeChoices = [0, 5, 9, 10, 15, 20]

    /// When it next rings after `now`, or nil when switched off.
    public static func nextRing(_ alarm: WakeAlarm, after now: Date, calendar: Calendar) -> Date? {
        guard alarm.enabled else { return nil }
        let hour = alarm.minutes / 60, minute = alarm.minutes % 60
        let startOfToday = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let ring = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  ring > now else { continue }
            if alarm.days.isEmpty || alarm.days.contains(calendar.component(.weekday, from: day)) { return ring }
        }
        return nil
    }

    /// The soonest ring among all alarms.
    public static func next(_ alarms: [WakeAlarm], after now: Date, calendar: Calendar) -> (alarm: WakeAlarm, at: Date)? {
        alarms.compactMap { a in nextRing(a, after: now, calendar: calendar).map { (a, $0) } }.min { $0.1 < $1.1 }
    }

    /// "Rings in 7 hr 23 min" / "Rings in 45 min" / "Rings in under a minute"
    public static func ringsIn(_ ring: Date, from now: Date) -> String {
        let total = Int(ring.timeIntervalSince(now) / 60)
        if total < 1 { return "Rings in under a minute" }
        let hours = total / 60, minutes = total % 60
        if hours == 0 { return "Rings in \(minutes) min" }
        if minutes == 0 { return "Rings in \(hours) hr" }
        return "Rings in \(hours) hr \(minutes) min"
    }

    /// "Every day", "Weekdays", "Weekends", "Mon, Wed, Fri", "Once"
    public static func daysText(_ days: [Int], calendar: Calendar) -> String {
        let set = Set(days)
        if set.isEmpty { return "Once" }
        if set.count == 7 { return "Every day" }
        if set == [2, 3, 4, 5, 6] { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        let names = calendar.shortWeekdaySymbols
        // Monday first, Sunday last
        return set.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { names[($0 - 1) % 7] }.joined(separator: ", ")
    }

    /// "7:30 AM"
    public static func timeText(_ minutes: Int, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? Locale(identifier: "en_US")
        f.timeStyle = .short
        f.dateStyle = .none
        let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(timeIntervalSince1970: 86_400 * 3)) ?? Date()
        return f.string(from: date)
    }

    /// One-time alarms that have already rung: switch them off. Returns the
    /// ids switched off (empty when nothing changed).
    public static func expireRungOnce(_ settings: inout AlarmClockSettings, now: Date) -> [String] {
        var changed: [String] = []
        for i in settings.alarms.indices {
            let a = settings.alarms[i]
            if a.enabled, !a.repeats, let at = a.onceAt, at <= now {
                settings.alarms[i].enabled = false
                settings.alarms[i].onceAt = nil
                changed.append(a.id)
            }
        }
        return changed
    }

    /// What the phone sets: one entry per alarm that's on.
    public static func specs(_ settings: AlarmClockSettings) -> [WidgetAlarmSpec] {
        settings.alarms.filter(\.enabled).map { a in
            let station = settings.station(id: a.stationId)
            return WidgetAlarmSpec(id: a.id, hour: a.minutes / 60, minute: a.minutes % 60, weekdays: a.days,
                                   title: title(a, station: station), stationName: station?.name,
                                   stationURL: station?.url, snoozeMinutes: a.snoozeMinutes)
        }
    }

    /// The alarm screen's title: the label, else the station, else "Wake up"
    public static func title(_ alarm: WakeAlarm, station: MusicStation?) -> String {
        let label = alarm.label.trimmingCharacters(in: .whitespaces)
        if !label.isEmpty { return label }
        if let station { return "Wake up to \(station.name)" }
        return "Wake up"
    }
}

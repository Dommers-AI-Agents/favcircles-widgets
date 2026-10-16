import Foundation

/// Weather (Wes, 2026-10-07): the temperature on the home header and a full
/// forecast widget. Saved cities like Apple's Weather app (2026-10-16): My
/// Location plus a list you search, add, reorder and delete. The home header
/// shows current location or one place (`mode`/`place`). Preferences live on
/// the phone (`WeatherPrefs.load/save`).
public struct WeatherPrefs: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case current, fixed }
    /// What the home header shows
    public var mode: Mode
    /// The header's place, when `mode == .fixed`
    public var place: WeatherPlace?
    /// nil = the phone's region (°F in the US)
    public var unit: WeatherUnit?
    /// Saved cities, in the user's order
    public var savedPlaces: [WeatherPlace]

    public static let maxSaved = 25

    public init(mode: Mode = .current, place: WeatherPlace? = nil, unit: WeatherUnit? = nil, savedPlaces: [WeatherPlace] = []) {
        self.mode = mode; self.place = place; self.unit = unit; self.savedPlaces = savedPlaces
    }

    enum CodingKeys: String, CodingKey { case mode, place, unit, savedPlaces }

    /// Prefs saved before the list existed have no `savedPlaces`: their one
    /// fixed place becomes the first saved city.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .current
        place = try c.decodeIfPresent(WeatherPlace.self, forKey: .place)
        unit = try c.decodeIfPresent(WeatherUnit.self, forKey: .unit)
        if let saved = try c.decodeIfPresent([WeatherPlace].self, forKey: .savedPlaces) {
            savedPlaces = saved
        } else {
            savedPlaces = place.map { [$0] } ?? []
        }
    }

    /// Whether `place` is already in the list (same ~1 km spot)
    public func isSaved(_ place: WeatherPlace) -> Bool {
        savedPlaces.contains { $0.sameSpot(as: place) }
    }

    /// Adds to the end; a place already there or a full list changes nothing.
    @discardableResult
    public mutating func addPlace(_ place: WeatherPlace) -> Bool {
        guard !isSaved(place), savedPlaces.count < Self.maxSaved else { return false }
        savedPlaces.append(place)
        return true
    }

    /// Removes a saved city; if the header showed it, the header goes back to
    /// current location.
    public mutating func removePlace(_ place: WeatherPlace) {
        savedPlaces.removeAll { $0.sameSpot(as: place) }
        if mode == .fixed, let shown = self.place, shown.sameSpot(as: place) {
            mode = .current
            self.place = nil
        }
    }

    public mutating func movePlaces(from source: IndexSet, to destination: Int) {
        // IndexSet move without SwiftUI: take the items out, put them back
        let moving = source.sorted().map { savedPlaces[$0] }
        var rest = savedPlaces.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        savedPlaces = rest
    }

    /// The header shows this place (nil = current location)
    public mutating func showOnHeader(_ place: WeatherPlace?) {
        if let place { mode = .fixed; self.place = place } else { mode = .current; self.place = nil }
    }

    /// The fixed place, if that's what's chosen (a fixed mode with no place falls back to current)
    public var fixedPlace: WeatherPlace? { mode == .fixed ? place : nil }

    public func resolvedUnit(locale: Locale = .current) -> WeatherUnit {
        unit ?? WeatherUnit.regionDefault(locale)
    }

    static let key = "favwidgets.weather.prefs"
    public static func load(_ defaults: UserDefaults = .standard) -> WeatherPrefs {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(WeatherPrefs.self, from: data) else { return WeatherPrefs() }
        return p
    }
    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

public struct WeatherPlace: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    /// For the row's local time ("3:20 AM" in Chandler); nil on places saved
    /// before 2026-10-16
    public let timeZoneId: String?
    public init(name: String, latitude: Double, longitude: Double, timeZoneId: String? = nil) {
        self.name = name; self.latitude = latitude; self.longitude = longitude; self.timeZoneId = timeZoneId
    }
    public var id: String { WeatherCachePolicy.key(latitude: latitude, longitude: longitude) }
    public func sameSpot(as other: WeatherPlace) -> Bool { id == other.id }
    public var timeZone: TimeZone? { timeZoneId.flatMap(TimeZone.init(identifier:)) }
}

/// The sky behind a row: night, clear, clouds, rain, snow or storm, from the
/// condition's SF Symbol (WeatherKit names them "moon.stars", "cloud.rain", …).
public enum WeatherSky: String, Sendable {
    case clearDay, clearNight, cloudy, cloudyNight, rain, snow, storm, fog

    public static func from(symbol: String) -> WeatherSky {
        let s = symbol.lowercased()
        let night = s.contains("moon")
        if s.contains("bolt") { return .storm }
        if s.contains("snow") || s.contains("sleet") || s.contains("hail") { return .snow }
        if s.contains("rain") || s.contains("drizzle") || s.contains("heavyrain") { return .rain }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") || s.contains("dust") { return .fog }
        if s.contains("cloud") { return night ? .cloudyNight : .cloudy }
        return night ? .clearNight : .clearDay
    }
}

public enum WeatherClock {
    /// "6:20 AM" where the place is
    public static func localTime(_ date: Date = Date(), in timeZone: TimeZone, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }
}

public enum WeatherUnit: String, Codable, CaseIterable, Sendable {
    case fahrenheit, celsius
    public var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    public static func regionDefault(_ locale: Locale) -> WeatherUnit {
        let region = locale.region?.identifier ?? "US"
        // The places that still use Fahrenheit
        return ["US", "BS", "BZ", "KY", "PW", "LR", "FM", "MH", "PR", "GU", "VI", "AS", "MP"].contains(region) ? .fahrenheit : .celsius
    }
}

/// One forecast, already mapped out of WeatherKit (temperatures in °C).
public struct WeatherForecast: Codable, Equatable, Sendable {
    public struct Now: Codable, Equatable, Sendable {
        public let tempC: Double, feelsLikeC: Double
        public let symbol: String, condition: String
        public let humidity: Double, windKph: Double, uvIndex: Int
        public init(tempC: Double, feelsLikeC: Double, symbol: String, condition: String, humidity: Double, windKph: Double, uvIndex: Int) {
            self.tempC = tempC; self.feelsLikeC = feelsLikeC; self.symbol = symbol; self.condition = condition
            self.humidity = humidity; self.windKph = windKph; self.uvIndex = uvIndex
        }
    }
    public struct Hour: Codable, Equatable, Sendable, Identifiable {
        public let date: Date, tempC: Double, symbol: String, precipChance: Double
        public var id: Date { date }
        public init(date: Date, tempC: Double, symbol: String, precipChance: Double) {
            self.date = date; self.tempC = tempC; self.symbol = symbol; self.precipChance = precipChance
        }
    }
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public let date: Date, lowC: Double, highC: Double, symbol: String, precipChance: Double
        public var id: Date { date }
        public init(date: Date, lowC: Double, highC: Double, symbol: String, precipChance: Double) {
            self.date = date; self.lowC = lowC; self.highC = highC; self.symbol = symbol; self.precipChance = precipChance
        }
    }
    public let placeName: String?
    public let now: Now
    public let hours: [Hour]
    public let days: [Day]
    public let fetchedAt: Date
    public init(placeName: String?, now: Now, hours: [Hour], days: [Day], fetchedAt: Date) {
        self.placeName = placeName; self.now = now; self.hours = hours; self.days = days; self.fetchedAt = fetchedAt
    }
}

public enum WeatherFormat {
    /// 22.4 °C → "72°" (F) / "22°" (C)
    public static func temp(_ celsius: Double, _ unit: WeatherUnit) -> String {
        "\(Int(converted(celsius, unit).rounded()))°"
    }
    public static func converted(_ celsius: Double, _ unit: WeatherUnit) -> Double {
        unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }
    /// km/h → "9 mph" / "15 km/h"
    public static func wind(_ kph: Double, _ unit: WeatherUnit) -> String {
        unit == .fahrenheit ? "\(Int((kph / 1.609344).rounded())) mph" : "\(Int(kph.rounded())) km/h"
    }
    /// 0.3 → "30%"; under 10% shows nothing (noise)
    public static func precip(_ chance: Double) -> String? {
        chance >= 0.1 ? "\(Int((chance * 100 / 10).rounded()) * 10)%" : nil
    }
}

/// When a cached forecast is still good, and which cache entry a location uses.
public enum WeatherCachePolicy {
    public static let freshFor: TimeInterval = 15 * 60
    /// ~1 km grid, so a few metres of GPS jitter doesn't refetch
    public static func key(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f,%.2f", latitude, longitude)
    }
    public static func isFresh(_ fetchedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) < freshFor && now >= fetchedAt
    }
}

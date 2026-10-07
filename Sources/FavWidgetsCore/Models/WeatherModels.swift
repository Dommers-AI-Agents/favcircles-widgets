import Foundation

/// Weather (Wes, 2026-10-07): the temperature on the home header and a full
/// forecast widget, for your current location or a place you pick that stays.
/// Preferences live on the phone (`WeatherPrefs.load/save`).
public struct WeatherPrefs: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case current, fixed }
    public var mode: Mode
    /// The place that stays, when `mode == .fixed`
    public var place: WeatherPlace?
    /// nil = the phone's region (°F in the US)
    public var unit: WeatherUnit?

    public init(mode: Mode = .current, place: WeatherPlace? = nil, unit: WeatherUnit? = nil) {
        self.mode = mode; self.place = place; self.unit = unit
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

public struct WeatherPlace: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name; self.latitude = latitude; self.longitude = longitude
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

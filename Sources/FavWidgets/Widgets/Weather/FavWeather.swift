import Foundation
import FavWidgetsCore
import CoreLocation
import WeatherKit

/// Weather for the home header and the Weather widget (2026-10-07), from
/// Apple's WeatherKit (the app holds the WeatherKit entitlement). One
/// forecast per ~1 km for 15 minutes, shared by both, so opening the widget
/// after glancing at the header costs nothing.
@MainActor
public final class FavWeather: ObservableObject {
    public static let shared = FavWeather()

    /// What the header shows: "72°" plus the condition's SF Symbol
    public struct Header: Equatable, Sendable {
        public let text: String
        public let symbolName: String
        public let accessibilityLabel: String
    }

    @Published public private(set) var header: Header?
    @Published public private(set) var prefs = WeatherPrefs.load()
    @Published public private(set) var latest: WeatherForecast?
    /// Current location was asked for but isn't available
    @Published public private(set) var locationUnavailable = false

    private var cache: [String: WeatherForecast] = [:]
    private var inFlight: [String: Task<WeatherForecast, Error>] = [:]

    private init() {}

    public func update(_ change: (inout WeatherPrefs) -> Void) {
        var p = prefs
        change(&p)
        guard p != prefs else { return }
        prefs = p
        p.save()
        if let latest { publishHeader(latest) }
    }

    /// The forecast for the chosen place, or where the phone is now.
    /// `currentLocation` is the host's (the app's) one-shot location fix.
    @discardableResult
    public func refresh(force: Bool = false, currentLocation: () async -> WidgetCoordinate?) async -> WeatherForecast? {
        let target: (lat: Double, lon: Double, name: String?)
        if let place = prefs.fixedPlace {
            target = (place.latitude, place.longitude, place.name)
        } else if let here = await currentLocation() {
            target = (here.latitude, here.longitude, nil)
        } else {
            locationUnavailable = true
            return latest
        }
        locationUnavailable = false
        do {
            let forecast = try await forecast(latitude: target.lat, longitude: target.lon, name: target.name, force: force)
            latest = forecast
            publishHeader(forecast)
            return forecast
        } catch {
            return latest
        }
    }

    private func forecast(latitude: Double, longitude: Double, name: String?, force: Bool) async throws -> WeatherForecast {
        let key = WeatherCachePolicy.key(latitude: latitude, longitude: longitude)
        if !force, let hit = cache[key], WeatherCachePolicy.isFresh(hit.fetchedAt) { return hit }
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await Self.fetch(latitude: latitude, longitude: longitude, name: name) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let result = try await task.value
        cache[key] = result
        return result
    }

    private func publishHeader(_ f: WeatherForecast) {
        let unit = prefs.resolvedUnit()
        let text = WeatherFormat.temp(f.now.tempC, unit)
        header = Header(text: text, symbolName: f.now.symbol,
                        accessibilityLabel: "\(text) and \(f.now.condition.lowercased())\(f.placeName.map { " in \($0)" } ?? ""). Weather")
    }

    // MARK: - WeatherKit

    nonisolated private static func fetch(latitude: Double, longitude: Double, name: String?) async throws -> WeatherForecast {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        async let placeName: String? = name != nil ? name : reverseName(location)
        let (current, hourly, daily) = try await WeatherService.shared.weather(for: location, including: .current, .hourly, .daily)
        let now = Date()
        let hours = hourly.forecast.filter { $0.date >= now.addingTimeInterval(-3600) }.prefix(24).map {
            WeatherForecast.Hour(date: $0.date, tempC: $0.temperature.converted(to: .celsius).value,
                                 symbol: $0.symbolName, precipChance: $0.precipitationChance)
        }
        let days = daily.forecast.prefix(10).map {
            WeatherForecast.Day(date: $0.date, lowC: $0.lowTemperature.converted(to: .celsius).value,
                                highC: $0.highTemperature.converted(to: .celsius).value,
                                symbol: $0.symbolName, precipChance: $0.precipitationChance)
        }
        return WeatherForecast(
            placeName: await placeName,
            now: .init(tempC: current.temperature.converted(to: .celsius).value,
                       feelsLikeC: current.apparentTemperature.converted(to: .celsius).value,
                       symbol: current.symbolName, condition: current.condition.description,
                       humidity: current.humidity,
                       windKph: current.wind.speed.converted(to: .kilometersPerHour).value,
                       uvIndex: current.uvIndex.value),
            hours: Array(hours), days: Array(days), fetchedAt: now)
    }

    nonisolated private static func reverseName(_ location: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let m = marks?.first else { return nil }
        return m.locality ?? m.subAdministrativeArea ?? m.administrativeArea ?? m.name
    }

    /// Apple's required "Weather" mark and data-sources link
    public func attribution() async -> (markLight: URL, markDark: URL, legal: URL)? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return (a.combinedMarkLightURL, a.combinedMarkDarkURL, a.legalPageURL)
    }
}

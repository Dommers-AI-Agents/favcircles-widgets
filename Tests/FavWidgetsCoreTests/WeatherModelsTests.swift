import Testing
import Foundation
@testable import FavWidgetsCore

struct WeatherModelsTests {
    @Test func temperaturesRoundInEitherUnit() {
        #expect(WeatherFormat.temp(22.4, .fahrenheit) == "72°")
        #expect(WeatherFormat.temp(22.4, .celsius) == "22°")
        #expect(WeatherFormat.temp(-0.4, .celsius) == "0°")
        #expect(WeatherFormat.temp(-10, .fahrenheit) == "14°")
    }

    @Test func windAndRainChance() {
        #expect(WeatherFormat.wind(16.09344, .fahrenheit) == "10 mph")
        #expect(WeatherFormat.wind(15.2, .celsius) == "15 km/h")
        #expect(WeatherFormat.precip(0.05) == nil)
        #expect(WeatherFormat.precip(0.34) == "30%")
    }

    @Test func unitFollowsTheRegionUnlessChosen() {
        #expect(WeatherUnit.regionDefault(Locale(identifier: "en_US")) == .fahrenheit)
        #expect(WeatherUnit.regionDefault(Locale(identifier: "en_GB")) == .celsius)
        #expect(WeatherPrefs(unit: .celsius).resolvedUnit(locale: Locale(identifier: "en_US")) == .celsius)
    }

    @Test func fixedPlaceOnlyWhenChosen() {
        let ny = WeatherPlace(name: "New York", latitude: 40.71, longitude: -74.0)
        #expect(WeatherPrefs(mode: .fixed, place: ny).fixedPlace == ny)
        #expect(WeatherPrefs(mode: .current, place: ny).fixedPlace == nil)
        #expect(WeatherPrefs(mode: .fixed, place: nil).fixedPlace == nil)
    }

    @Test func prefsStayAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "weather-tests-\(UUID())"))
        #expect(WeatherPrefs.load(defaults) == WeatherPrefs())
        let p = WeatherPrefs(mode: .fixed, place: WeatherPlace(name: "Charlotte", latitude: 35.2, longitude: -80.8), unit: .fahrenheit)
        p.save(defaults)
        #expect(WeatherPrefs.load(defaults) == p)
    }

    @Test func cacheIsFifteenMinutesOnAOneKilometreGrid() {
        let now = Date()
        #expect(WeatherCachePolicy.isFresh(now.addingTimeInterval(-60), now: now))
        #expect(!WeatherCachePolicy.isFresh(now.addingTimeInterval(-16 * 60), now: now))
        #expect(WeatherCachePolicy.key(latitude: 35.22709, longitude: -80.84313) == WeatherCachePolicy.key(latitude: 35.2268, longitude: -80.8429))
    }
}

struct WeatherSavedPlacesTests {
    let belmar = WeatherPlace(name: "Belmar, NJ", latitude: 40.1784, longitude: -74.0218, timeZoneId: "America/New_York")
    let chandler = WeatherPlace(name: "Chandler, AZ", latitude: 33.3062, longitude: -111.8413, timeZoneId: "America/Phoenix")
    let asheville = WeatherPlace(name: "Asheville, NC", latitude: 35.5951, longitude: -82.5515)

    @Test func oldPrefsKeepTheirPlaceAsTheFirstSavedCity() throws {
        let old = #"{"mode":"fixed","place":{"name":"Belmar, NJ","latitude":40.1784,"longitude":-74.0218},"unit":"fahrenheit"}"#
        let prefs = try JSONDecoder().decode(WeatherPrefs.self, from: Data(old.utf8))
        #expect(prefs.savedPlaces.map(\.name) == ["Belmar, NJ"])
        #expect(prefs.fixedPlace?.name == "Belmar, NJ")
        #expect(prefs.savedPlaces.first?.timeZoneId == nil)
        let none = try JSONDecoder().decode(WeatherPrefs.self, from: Data(#"{"mode":"current"}"#.utf8))
        #expect(none.savedPlaces.isEmpty)
    }

    @Test func addDedupesMoveAndRemove() {
        var prefs = WeatherPrefs()
        let first = prefs.addPlace(belmar)
        let again = prefs.addPlace(WeatherPlace(name: "Belmar", latitude: 40.1781, longitude: -74.0219)) // same spot
        #expect(first)
        #expect(!again)
        prefs.addPlace(chandler)
        prefs.addPlace(asheville)
        prefs.movePlaces(from: IndexSet(integer: 2), to: 0)
        #expect(prefs.savedPlaces.map(\.name) == ["Asheville, NC", "Belmar, NJ", "Chandler, AZ"])
        prefs.movePlaces(from: IndexSet(integer: 0), to: 3)
        #expect(prefs.savedPlaces.map(\.name) == ["Belmar, NJ", "Chandler, AZ", "Asheville, NC"])
        prefs.showOnHeader(chandler)
        prefs.removePlace(chandler)
        #expect(prefs.savedPlaces.map(\.name) == ["Belmar, NJ", "Asheville, NC"])
        #expect(prefs.mode == .current) // the header followed it away
    }

    @Test func listHasACap() {
        var prefs = WeatherPrefs()
        for i in 0..<WeatherPrefs.maxSaved { prefs.addPlace(WeatherPlace(name: "\(i)", latitude: Double(i), longitude: 0)) }
        let added = prefs.addPlace(belmar)
        #expect(!added)
    }

    @Test func skyFromTheSymbol() {
        #expect(WeatherSky.from(symbol: "moon.stars") == .clearNight)
        #expect(WeatherSky.from(symbol: "sun.max") == .clearDay)
        #expect(WeatherSky.from(symbol: "cloud.moon") == .cloudyNight)
        #expect(WeatherSky.from(symbol: "cloud.rain") == .rain)
        #expect(WeatherSky.from(symbol: "cloud.bolt.rain") == .storm)
        #expect(WeatherSky.from(symbol: "cloud.snow") == .snow)
        #expect(WeatherSky.from(symbol: "cloud.fog") == .fog)
    }

    @Test func localTimeWhereThePlaceIs() {
        let date = Date(timeIntervalSince1970: 1_792_145_000) // 2026-10-16 10:03 UTC
        let en = Locale(identifier: "en_US")
        #expect(WeatherClock.localTime(date, in: TimeZone(identifier: "America/Phoenix")!, locale: en) == "3:03 AM")
        #expect(WeatherClock.localTime(date, in: TimeZone(identifier: "America/New_York")!, locale: en) == "6:03 AM")
    }
}

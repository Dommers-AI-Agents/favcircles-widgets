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

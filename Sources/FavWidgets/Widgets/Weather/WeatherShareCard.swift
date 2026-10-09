import FavWidgetsCore

extension WeatherWidget {
    /// Now, high and low, and the place the user is looking at.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let weather = FavWeather.shared
        guard let f = weather.latest else { return nil }
        let unit = weather.prefs.resolvedUnit()
        return .weather(temp: WeatherFormat.temp(f.now.tempC, unit), condition: f.now.condition,
                        high: f.days.first.map { WeatherFormat.temp($0.highC, unit) },
                        low: f.days.first.map { WeatherFormat.temp($0.lowC, unit) },
                        place: f.placeName)
    }
}

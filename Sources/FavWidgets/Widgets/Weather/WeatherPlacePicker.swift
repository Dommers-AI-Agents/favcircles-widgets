import Foundation
import MapKit
import FavWidgetsCore

/// Cities and airports for the Weather search field (Apple Maps), each with
/// its time zone so the list can show the local time.
enum WeatherPlaceSearch {
    static func search(_ query: String) async -> [WeatherPlace] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        var seen = Set<String>()
        return items.compactMap { item in
            let pm = item.placemark
            let isAirport = item.pointOfInterestCategory == .airport
            // Only places a forecast makes sense for: towns and airports
            if item.pointOfInterestCategory != nil && !isAirport { return nil }
            let town = isAirport ? (item.name ?? pm.locality) : (pm.locality ?? pm.name)
            let abroad = pm.countryCode != "US"
            let name = [town, pm.administrativeArea, abroad ? pm.country : nil]
                .compactMap { $0 }.joined(separator: ", ")
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return WeatherPlace(name: name, latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude,
                                timeZoneId: item.timeZone?.identifier)
        }
    }
}

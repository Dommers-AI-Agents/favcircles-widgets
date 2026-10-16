import Foundation

/// The live rain radar on a place's weather page (Wes, 2026-10-16).
///
/// The images are the National Weather Service's NEXRAD composite, served as
/// map tiles by Iowa State's mesonet (free, updated about every 5 minutes).
/// The phone loads them straight from there, so the backend pays nothing.
/// NEXRAD covers the US, so the card shows only for places it can see.
public enum WeatherRadar {
    /// Base reflectivity, the standard "rain on radar" picture.
    public static let tileTemplate = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"

    /// Shown under the map: the data's source, as the mesonet asks.
    public static let credit = "Radar: NOAA NEXRAD via Iowa Environmental Mesonet"

    /// Roughly how far the card shows around the place, like Apple's
    /// Precipitation map: a few states across.
    public static let spanDegrees = 7.0

    /// Lower 48, Alaska, Hawaii and Puerto Rico: where NEXRAD has radars.
    public static func covers(latitude: Double, longitude: Double) -> Bool {
        let boxes: [(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)] = [
            (24.0, 50.0, -125.5, -66.0),   // contiguous US
            (51.0, 71.5, -170.0, -129.0),  // Alaska
            (18.5, 22.5, -161.0, -154.5),  // Hawaii
            (17.5, 18.8, -67.5, -65.0)     // Puerto Rico
        ]
        return boxes.contains { latitude >= $0.minLat && latitude <= $0.maxLat && longitude >= $0.minLng && longitude <= $0.maxLng }
    }
}

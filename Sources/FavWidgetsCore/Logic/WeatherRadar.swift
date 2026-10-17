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

    // MARK: - Playback

    /// One picture of the radar, `minutesAgo` before the latest.
    public struct Frame: Equatable, Sendable {
        public let minutesAgo: Int
        public init(minutesAgo: Int) { self.minutesAgo = minutesAgo }

        /// The mesonet keeps a layer per 5 minutes: `-m05m` … `-m50m`.
        public var tileTemplate: String {
            guard minutesAgo > 0 else { return WeatherRadar.tileTemplate }
            return WeatherRadar.tileTemplate.replacingOccurrences(
                of: "nexrad-n0q-900913/", with: String(format: "nexrad-n0q-900913-m%02dm/", minutesAgo))
        }

        /// "Now", "5 min ago", "50 min ago"
        public var label: String { minutesAgo == 0 ? "Now" : "\(minutesAgo) min ago" }
    }

    /// Oldest first, ending on now: what playback steps through.
    public static let frames: [Frame] = stride(from: 50, through: 0, by: -5).map(Frame.init)

    /// The frame after `index`, holding a beat on "Now" before looping:
    /// returns the next index, or nil to pause there one extra tick.
    public static func nextIndex(after index: Int, holdTicks: Int, held: Int) -> (index: Int, held: Int) {
        let last = frames.count - 1
        if index >= last {
            return held < holdTicks ? (last, held + 1) : (0, 0)
        }
        return (index + 1, 0)
    }

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

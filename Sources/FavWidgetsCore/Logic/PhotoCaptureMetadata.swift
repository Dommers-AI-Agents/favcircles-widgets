import Foundation

/// Where and when a photo was taken, from the file's own GPS and EXIF
/// (the event album records it so a photo can be placed at the bar it was
/// taken in). Takes ImageIO's property dictionaries as plain dictionaries,
/// so this half is Foundation-only and tested on a Mac; the `FavWidgets`
/// layer reads them off the picked bytes. Same rules as the app's
/// PhotoMetadataReader ("Places from your photos").
public struct PhotoCaptureMetadata: Equatable, Sendable {
    public var coordinate: WidgetCoordinate?
    public var takenAt: Date?

    public init(coordinate: WidgetCoordinate? = nil, takenAt: Date? = nil) {
        self.coordinate = coordinate
        self.takenAt = takenAt
    }

    public var isEmpty: Bool { coordinate == nil && takenAt == nil }

    /// From the GPS, Exif and TIFF dictionaries ImageIO returns (the keys
    /// are the strings behind `kCGImagePropertyGPSLatitude` and friends).
    public static func from(gps: [String: Any]?, exif: [String: Any]?, tiff: [String: Any]?,
                            timeZone: TimeZone = .current) -> PhotoCaptureMetadata {
        PhotoCaptureMetadata(coordinate: coordinate(fromGPS: gps), takenAt: takenAt(exif: exif, tiff: tiff, timeZone: timeZone))
    }

    /// ImageIO stores unsigned degrees with a hemisphere ref. (0, 0) is a
    /// camera that wrote the block without a fix, not the Gulf of Guinea.
    public static func coordinate(fromGPS gps: [String: Any]?) -> WidgetCoordinate? {
        guard let gps, var lat = number(gps["Latitude"]), var lon = number(gps["Longitude"]) else { return nil }
        if (gps["LatitudeRef"] as? String)?.uppercased() == "S" { lat = -abs(lat) }
        if (gps["LongitudeRef"] as? String)?.uppercased() == "W" { lon = -abs(lon) }
        guard lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { return nil }
        return WidgetCoordinate(latitude: lat, longitude: lon)
    }

    /// "2026:10:04 14:10:05" plus "-04:00" when the camera recorded the
    /// offset; without one, `timeZone` (the phone's, by default).
    public static func takenAt(exif: [String: Any]?, tiff: [String: Any]?, timeZone: TimeZone = .current) -> Date? {
        let stamp = (exif?["DateTimeOriginal"] as? String)
            ?? (exif?["DateTimeDigitized"] as? String)
            ?? (tiff?["DateTime"] as? String)
        guard let stamp else { return nil }
        let offset = (exif?["OffsetTimeOriginal"] as? String) ?? (exif?["OffsetTime"] as? String)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if let offset {
            f.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = f.date(from: stamp + offset) { return date }
        }
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = timeZone
        return f.date(from: stamp)
    }

    /// The optional fields on `POST widgets/events/:id/photos`: `lat`,
    /// `lng` and `takenAt` (ISO 8601, UTC). Nothing when there's nothing.
    public var requestFields: [String: Any] {
        var fields: [String: Any] = [:]
        if let coordinate {
            fields["lat"] = coordinate.latitude
            fields["lng"] = coordinate.longitude
        }
        if let takenAt { fields["takenAt"] = Self.iso.string(from: takenAt) }
        return fields
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        return nil
    }
}

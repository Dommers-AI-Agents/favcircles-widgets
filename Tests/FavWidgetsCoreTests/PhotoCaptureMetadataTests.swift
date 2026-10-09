import Testing
import Foundation
@testable import FavWidgetsCore

struct PhotoCaptureMetadataTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-10-04 14:10:05 in Charlotte (UTC-4)
    private let expected = ISO8601DateFormatter().date(from: "2026-10-04T18:10:05Z")!

    @Test func hemisphereRefsSignTheDegrees() {
        let charlotte = PhotoCaptureMetadata.coordinate(fromGPS: ["Latitude": 35.2271, "LatitudeRef": "N", "Longitude": 80.8431, "LongitudeRef": "W"])
        #expect(charlotte == WidgetCoordinate(latitude: 35.2271, longitude: -80.8431))
        let sydney = PhotoCaptureMetadata.coordinate(fromGPS: ["Latitude": NSNumber(value: 33.8688), "LatitudeRef": "S", "Longitude": NSNumber(value: 151.2093), "LongitudeRef": "E"])
        #expect(sydney == WidgetCoordinate(latitude: -33.8688, longitude: 151.2093))
    }

    @Test func noFixMeansNoCoordinate() {
        #expect(PhotoCaptureMetadata.coordinate(fromGPS: nil) == nil)
        #expect(PhotoCaptureMetadata.coordinate(fromGPS: [:]) == nil)
        #expect(PhotoCaptureMetadata.coordinate(fromGPS: ["Latitude": 0.0, "Longitude": 0.0]) == nil)
        #expect(PhotoCaptureMetadata.coordinate(fromGPS: ["Latitude": 95.0, "Longitude": 10.0]) == nil)
        #expect(PhotoCaptureMetadata.coordinate(fromGPS: ["Latitude": "35.2", "Longitude": 10.0]) == nil)
    }

    @Test func captureTimeHonorsTheCameraOffset() {
        let exif: [String: Any] = ["DateTimeOriginal": "2026:10:04 14:10:05", "OffsetTimeOriginal": "-04:00"]
        let date = PhotoCaptureMetadata.takenAt(exif: exif, tiff: nil, timeZone: utc)
        #expect(date == expected)
    }

    @Test func captureTimeFallsBackToTheGivenZoneAndTiff() {
        let noOffset = PhotoCaptureMetadata.takenAt(exif: ["DateTimeOriginal": "2026:10:04 18:10:05"], tiff: nil, timeZone: utc)
        #expect(noOffset == expected)
        let tiffOnly = PhotoCaptureMetadata.takenAt(exif: nil, tiff: ["DateTime": "2026:10:04 18:10:05"], timeZone: utc)
        #expect(tiffOnly == expected)
        #expect(PhotoCaptureMetadata.takenAt(exif: ["DateTimeOriginal": "yesterday"], tiff: nil, timeZone: utc) == nil)
        #expect(PhotoCaptureMetadata.takenAt(exif: nil, tiff: nil, timeZone: utc) == nil)
    }

    @Test func requestFieldsCarryOnlyWhatWasRead() {
        let full = PhotoCaptureMetadata.from(gps: ["Latitude": 35.2271, "LatitudeRef": "N", "Longitude": 80.8431, "LongitudeRef": "W"],
                                             exif: ["DateTimeOriginal": "2026:10:04 14:10:05", "OffsetTimeOriginal": "-04:00"],
                                             tiff: nil, timeZone: utc)
        #expect(full.requestFields["lat"] as? Double == 35.2271)
        #expect(full.requestFields["lng"] as? Double == -80.8431)
        #expect(full.requestFields["takenAt"] as? String == "2026-10-04T18:10:05Z")
        let none = PhotoCaptureMetadata.from(gps: nil, exif: nil, tiff: nil)
        #expect(none.isEmpty)
        #expect(none.requestFields.isEmpty)
        let timeOnly = PhotoCaptureMetadata(takenAt: Date(timeIntervalSince1970: 0))
        #expect(timeOnly.requestFields.keys.sorted() == ["takenAt"])
    }
}

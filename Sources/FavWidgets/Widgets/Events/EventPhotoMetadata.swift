import Foundation
import FavWidgetsCore
#if canImport(ImageIO)
import ImageIO
#endif

extension PhotoCaptureMetadata {
    /// Reads the GPS and capture time off a picked photo's own bytes. Must
    /// run on the data from the picker: once it's a UIImage, and once
    /// `EventImagePrep` re-encodes it, there is nothing left to read.
    static func read(from data: Data) -> PhotoCaptureMetadata {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return PhotoCaptureMetadata() }
        return from(gps: props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
                    exif: props[kCGImagePropertyExifDictionary as String] as? [String: Any],
                    tiff: props[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        #else
        return PhotoCaptureMetadata()
        #endif
    }
}

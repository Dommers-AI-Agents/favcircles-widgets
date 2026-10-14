import Foundation

/// A 64-bit "difference hash" of a picture, so the event album can tell that
/// the same photo is being added twice (Wes, 2026-10-14). Takes the picture
/// already shrunk to 9×8 grey values (the `FavWidgets` layer draws that), so
/// this half is Foundation-only and tested on a Mac. A re-saved or
/// re-compressed copy lands within a bit or two of the original; the server
/// compares with a small tolerance.
public enum PhotoFingerprint {
    public static let width = 9
    public static let height = 8

    /// 16 lowercase hex characters, or nil unless `luma` is exactly 9×8 values.
    /// Each bit is "is this pixel brighter than its right-hand neighbour".
    public static func hash(luma: [UInt8]) -> String? {
        guard luma.count == width * height else { return nil }
        var bits: UInt64 = 0
        for row in 0..<height {
            for col in 0..<(width - 1) {
                bits <<= 1
                if luma[row * width + col] > luma[row * width + col + 1] { bits |= 1 }
            }
        }
        let hex = String(bits, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

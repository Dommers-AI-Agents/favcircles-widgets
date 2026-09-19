import Foundation

/// Lenient number parsing for typed fields ("1,5" and "1.5" both work).
public enum CalorieNumberParsing {
    public static func decimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0, value.isFinite else { return nil }
        return value
    }

    public static func integer(_ text: String) -> Int? {
        guard let value = decimal(text) else { return nil }
        return Int(value.rounded())
    }

    public static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

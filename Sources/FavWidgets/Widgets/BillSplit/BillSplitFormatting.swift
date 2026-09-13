import Foundation
import FavWidgetsCore

/// Pure formatting for the bill split widget: currency strings, input
/// parsing, and the share text. No UI, so it is unit-tested directly.
public enum BillSplitFormatting {
    /// Tip presets shown as segments; anything else is "Custom".
    public static let tipPresets = [15, 18, 20, 25]

    public static func currencyFormatter(locale: Locale = .current) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    public static func money(_ value: Decimal, locale: Locale = .current) -> String {
        let formatter = currencyFormatter(locale: locale)
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? formatter.currencySymbol + NSDecimalNumber(decimal: value).stringValue
    }

    /// The symbol shown as a text-field prefix ("$", "€").
    public static func currencySymbol(locale: Locale = .current) -> String {
        let symbol = currencyFormatter(locale: locale).currencySymbol ?? "$"
        return symbol.isEmpty ? "$" : symbol
    }

    /// Parses what the user typed. Empty or unreadable input is 0; a
    /// locale-specific decimal separator is accepted, and so is ".".
    public static func parseAmount(_ text: String, locale: Locale = .current) -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if let value = Decimal(string: trimmed, locale: locale), value >= 0 { return value }
        if let value = Decimal(string: trimmed), value >= 0 { return value }
        return 0
    }

    /// Card summary: "18% tip · 2 people".
    public static func summary(tipPercent: Int, people: Int) -> String {
        "\(tipPercent)% tip · \(people) \(people == 1 ? "person" : "people")"
    }

    /// What everyone pays when each share was rounded up.
    public static func totalCollected(perPerson: Decimal, people: Int) -> Decimal {
        perPerson * Decimal(max(1, people))
    }

    /// "Bill $100.00 + tax $8.00 + 18% tip $18.00 = $126.00 → 3 people, $42.00 each".
    /// The tax segment is left out when there is no tax.
    public static func shareText(
        subtotal: Decimal,
        tax: Decimal,
        tipPercent: Int,
        result: BillSplitResult,
        people: Int,
        locale: Locale = .current
    ) -> String {
        let people = max(1, people)
        var text = "Bill \(money(subtotal, locale: locale))"
        if tax > 0 {
            text += " + tax \(money(tax, locale: locale))"
        }
        text += " + \(tipPercent)% tip \(money(result.tip, locale: locale))"
        text += " = \(money(result.total, locale: locale))"
        text += " → \(people) \(people == 1 ? "person" : "people"), \(money(result.perPerson, locale: locale)) each"
        return text
    }
}

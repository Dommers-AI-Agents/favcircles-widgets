import Foundation

/// How a printed postcard's price reads while a special is on
/// ("$1.99 today only", Wes 2026-10-08): the regular price struck through,
/// the special price, and its label. The server decides both prices.
public enum PostcardPriceCopy {
    /// The struck-through regular price, or nil when there's no special
    public static func was(priceCents: Int, regularPriceCents: Int?) -> String? {
        guard let regular = regularPriceCents, regular > priceCents else { return nil }
        return PostcardMailOrder.price(cents: regular)
    }

    public static func now(priceCents: Int) -> String { PostcardMailOrder.price(cents: priceCents) }

    /// The card badge: "$1.99 · Today only"; nil with no special running
    public static func badge(priceCents: Int, regularPriceCents: Int?, label: String?) -> String? {
        guard was(priceCents: priceCents, regularPriceCents: regularPriceCents) != nil else { return nil }
        let tag = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tag.isEmpty ? "\(now(priceCents: priceCents)) special" : "\(now(priceCents: priceCents)) · \(tag)"
    }
}

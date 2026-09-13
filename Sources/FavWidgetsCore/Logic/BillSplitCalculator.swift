import Foundation

public struct BillSplitResult: Equatable, Sendable {
    public let tip: Decimal
    public let total: Decimal
    public let perPerson: Decimal

    public init(tip: Decimal, total: Decimal, perPerson: Decimal) {
        self.tip = tip
        self.total = total
        self.perPerson = perPerson
    }
}

public enum BillSplitCalculator {
    /// Decimal math, rounded to cents. `roundUp` bumps each share to the
    /// next whole unit so nobody argues over coins.
    public static func split(
        subtotal: Decimal,
        tax: Decimal = 0,
        tipPercent: Int,
        tipOnPreTax: Bool = true,
        people: Int,
        roundUp: Bool = false
    ) -> BillSplitResult {
        let people = max(1, people)
        let tipBase = tipOnPreTax ? subtotal : subtotal + tax
        let tip = roundCents(tipBase * Decimal(max(0, tipPercent)) / 100)
        let total = roundCents(subtotal + tax + tip)
        var share = roundCents(total / Decimal(people))
        if roundUp {
            var rounded = Decimal()
            var value = share
            NSDecimalRound(&rounded, &value, 0, .up)
            share = rounded
        }
        return BillSplitResult(tip: tip, total: total, perPerson: share)
    }

    public static func roundCents(_ value: Decimal) -> Decimal {
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded
    }
}

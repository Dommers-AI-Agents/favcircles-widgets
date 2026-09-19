import Testing
import Foundation
@testable import FavWidgetsCore

private let us = Locale(identifier: "en_US")

struct BillSplitFormattingTests {
    @Test func shareTextMatchesSpecExample() {
        let result = BillSplitCalculator.split(subtotal: 100, tax: 8, tipPercent: 18, tipOnPreTax: true, people: 3)
        let text = BillSplitFormatting.shareText(subtotal: 100, tax: 8, tipPercent: 18, result: result, people: 3, locale: us)
        #expect(text == "Bill $100.00 + tax $8.00 + 18% tip $18.00 = $126.00 → 3 people, $42.00 each")
    }

    @Test func shareTextOmitsZeroTaxAndUsesSingular() {
        let result = BillSplitCalculator.split(subtotal: 40, tax: 0, tipPercent: 20, people: 1)
        let text = BillSplitFormatting.shareText(subtotal: 40, tax: 0, tipPercent: 20, result: result, people: 1, locale: us)
        #expect(text == "Bill $40.00 + 20% tip $8.00 = $48.00 → 1 person, $48.00 each")
    }

    @Test func roundUpCollectsMoreThanTotal() {
        let result = BillSplitCalculator.split(subtotal: 100, tax: 0, tipPercent: 0, people: 3, roundUp: true)
        #expect(result.perPerson == 34)
        #expect(BillSplitFormatting.totalCollected(perPerson: result.perPerson, people: 3) == 102)
    }

    @Test func parsesAmountsLeniently() {
        #expect(BillSplitFormatting.parseAmount("", locale: us) == 0)
        #expect(BillSplitFormatting.parseAmount(" 12.50 ", locale: us) == Decimal(string: "12.50"))
        #expect(BillSplitFormatting.parseAmount("abc", locale: us) == 0)
        #expect(BillSplitFormatting.parseAmount("-5", locale: us) == 0)
        #expect(BillSplitFormatting.parseAmount("12,50", locale: Locale(identifier: "de_DE")) == Decimal(string: "12.50"))
    }

    @Test func summaryAndSymbol() {
        #expect(BillSplitFormatting.summary(tipPercent: 18, people: 2) == "18% tip · 2 people")
        #expect(BillSplitFormatting.summary(tipPercent: 20, people: 1) == "20% tip · 1 person")
        #expect(BillSplitFormatting.currencySymbol(locale: us) == "$")
        #expect(BillSplitFormatting.money(Decimal(string: "1234.5")!, locale: us) == "$1,234.50")
    }
}

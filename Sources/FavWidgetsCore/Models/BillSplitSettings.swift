import Foundation

/// Only the last-used defaults are stored; a split is a calculation, not a
/// record.
public struct BillSplitSettings: WidgetModel {
    public var lastTipPercent: Int
    public var roundUp: Bool
    public var defaultPeople: Int
    public var tipOnPreTax: Bool
    public var lastPlace: WidgetPlaceRef?

    public init(lastTipPercent: Int = 18, roundUp: Bool = false, defaultPeople: Int = 2, tipOnPreTax: Bool = true, lastPlace: WidgetPlaceRef? = nil) {
        self.lastTipPercent = lastTipPercent
        self.roundUp = roundUp
        self.defaultPeople = defaultPeople
        self.tipOnPreTax = tipOnPreTax
        self.lastPlace = lastPlace
    }

    public static let empty = BillSplitSettings()
}

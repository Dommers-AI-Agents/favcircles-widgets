import Foundation

/// Calories plus the three macros, in kcal and grams.
public struct MacroTotals: Codable, Equatable, Sendable {
    public var kcal: Int
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Int = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = MacroTotals()

    public static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
                    carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    public static func sum(_ entries: [FoodEntry]) -> MacroTotals {
        entries.reduce(.zero) { $0 + $1.macros }
    }
}

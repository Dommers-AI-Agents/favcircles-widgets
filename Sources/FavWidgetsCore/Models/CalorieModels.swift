import Foundation

/// One logged food. Macros are optional because most people only track
/// calories.
public struct FoodEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kcal: Int
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var loggedAt: Date

    public init(id: UUID = UUID(), name: String, kcal: Int, protein: Double? = nil,
                carbs: Double? = nil, fat: Double? = nil, loggedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.loggedAt = loggedAt
    }

    public var macros: MacroTotals {
        MacroTotals(kcal: kcal, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
    }
}

/// A food the user logs often, kept for one-tap re-adding.
public struct FoodPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kcal: Int
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?

    public init(id: UUID = UUID(), name: String, kcal: Int, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.id = id
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public init(from entry: FoodEntry) {
        self.init(name: entry.name, kcal: entry.kcal, protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
    }

    public func entry(at date: Date = Date()) -> FoodEntry {
        FoodEntry(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat, loggedAt: date)
    }
}

/// Settings document (`calories`): goals and the quick-add list.
public struct CalorieSettings: WidgetModel {
    public var dailyGoalKcal: Int
    public var macroGoals: MacroTotals?
    /// Most recent distinct foods, newest first. A UX list capped at
    /// `recentLimit`; the logged entries themselves are never trimmed.
    public var recentFoods: [FoodPreset]

    public static let recentLimit = 30

    public init(dailyGoalKcal: Int = 2000, macroGoals: MacroTotals? = nil, recentFoods: [FoodPreset] = []) {
        self.dailyGoalKcal = dailyGoalKcal
        self.macroGoals = macroGoals
        self.recentFoods = recentFoods
    }

    public static let empty = CalorieSettings()

    public mutating func noteRecent(_ entry: FoodEntry) {
        let key = entry.name.lowercased()
        recentFoods.removeAll { $0.name.lowercased() == key }
        recentFoods.insert(FoodPreset(from: entry), at: 0)
        if recentFoods.count > Self.recentLimit {
            recentFoods.removeLast(recentFoods.count - Self.recentLimit)
        }
    }
}

/// One month of entries (`calories_yyyy-MM`), keyed by day.
public struct CalorieMonth: WidgetModel {
    public var days: [DayKey: [FoodEntry]]

    public init(days: [DayKey: [FoodEntry]] = [:]) {
        self.days = days
    }

    public static let empty = CalorieMonth()

    public func entries(on day: DayKey) -> [FoodEntry] {
        (days[day] ?? []).sorted { $0.loggedAt < $1.loggedAt }
    }

    public func totals(on day: DayKey) -> MacroTotals {
        MacroTotals.sum(days[day] ?? [])
    }

    public mutating func add(_ entry: FoodEntry, on day: DayKey) {
        days[day, default: []].append(entry)
    }

    public mutating func remove(id: UUID, on day: DayKey) {
        days[day]?.removeAll { $0.id == id }
        if days[day]?.isEmpty == true { days[day] = nil }
    }

    /// Two devices logging the same day: keep every entry from both.
    public static func merge(local: CalorieMonth, remote: CalorieMonth) -> CalorieMonth {
        var merged = local
        for (day, remoteEntries) in remote.days {
            var entries = merged.days[day] ?? []
            let known = Set(entries.map(\.id))
            entries.append(contentsOf: remoteEntries.filter { !known.contains($0.id) })
            merged.days[day] = entries
        }
        return merged
    }
}

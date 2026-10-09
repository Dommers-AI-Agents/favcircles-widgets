import Foundation
import FavWidgetsCore

extension WorkoutWidget {
    /// The latest finished workout (this month or last): name, date, minutes,
    /// exercises, sets. A finished workout's own Share stays the full card.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        var latest: WorkoutSession?
        for key in [context.currentMonth, context.currentMonth.previous] {
            let month = context.month(WorkoutMonth.self, key)
            await month.loadIfNeeded()
            for s in month.model.sessions where s.endedAt != nil && s.startedAt > (latest?.startedAt ?? .distantPast) { latest = s }
        }
        guard let s = latest, let ended = s.endedAt else { return nil }
        let done = s.sets.filter { $0.completedAt != nil && !$0.isWarmup }
        return .workout(name: s.name, startedAt: s.startedAt, minutes: Int(ended.timeIntervalSince(s.startedAt) / 60),
                        exercises: Set(done.map(\.exerciseId)).count, sets: done.count,
                        cardioMinutes: s.cardio.reduce(0) { $0 + $1.minutes }, calendar: context.calendar)
    }
}

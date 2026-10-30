import Foundation

/// The workout in progress as the lock screen shows it (2026-10-30, Wes:
/// "a persistent notification so it's easier to update each set without
/// navigating to the workout widget"): the next set to do, with the numbers
/// it would be ticked at, and how far along the workout is. Pure.
public struct WorkoutLiveState: Equatable, Sendable {
    public struct NextSet: Equatable, Sendable {
        public let setId: UUID
        public let exerciseName: String
        /// 1-based, within the exercise
        public let setNumber: Int
        public let setsInExercise: Int
        public let reps: Int?
        public let weight: Double?
        public let isWarmup: Bool
    }

    public let sessionId: UUID
    public let name: String
    public let startedAt: Date
    public let doneSets: Int
    public let totalSets: Int
    /// nil when every set is done (open the app to finish)
    public let next: NextSet?
    public let unit: WeightUnit

    /// "135 lb × 8" / "8 reps" / "135 lb" / nil when nothing is known yet
    public var nextNumbers: String? {
        guard let next else { return nil }
        let weight = next.weight.flatMap { $0 > 0 ? "\(WorkoutNumber.trim($0)) \(unit.label)" : nil }
        let reps = next.reps.flatMap { $0 > 0 ? $0 : nil }
        switch (weight, reps) {
        case let (w?, r?): return "\(w) × \(r)"
        case let (w?, nil): return w
        case let (nil, r?): return "\(r) reps"
        default: return nil
        }
    }

    /// "Set 2 of 4" / "Warm-up · set 1 of 4"
    public var nextSetLabel: String? {
        guard let next else { return nil }
        let label = "Set \(next.setNumber) of \(next.setsInExercise)"
        return next.isWarmup ? "Warm-up · \(label.lowercased())" : label
    }
}

public enum WorkoutLivePlan {
    /// nil when there's no workout in progress.
    public static func state(_ settings: WorkoutSettings) -> WorkoutLiveState? {
        guard let session = settings.activeSession else { return nil }
        let routines = settings.routines + ExerciseCatalog.starterRoutines
        var next: WorkoutLiveState.NextSet?
        for exerciseId in WorkoutSessionLogic.orderedExerciseIds(in: session) {
            let sets = session.sets.filter { $0.exerciseId == exerciseId }
            guard let index = sets.firstIndex(where: { $0.completedAt == nil }) else { continue }
            let target = Self.target(at: index, sets: sets, exerciseId: exerciseId, session: session, routines: routines)
            let set = sets[index]
            next = WorkoutLiveState.NextSet(
                setId: set.id,
                exerciseName: settings.exercise(id: exerciseId)?.name ?? "Exercise",
                setNumber: index + 1,
                setsInExercise: sets.count,
                reps: set.reps > 0 ? set.reps : target.reps,
                weight: set.weight > 0 ? set.weight : target.weight,
                isWarmup: set.isWarmup)
            break
        }
        return WorkoutLiveState(sessionId: session.id, name: session.name, startedAt: session.startedAt,
                                doneSets: WorkoutSessionLogic.completedSetCount(session), totalSets: session.sets.count,
                                next: next, unit: settings.unit)
    }

    /// Ticks `setId` done the way its row would (the target it offers fills
    /// an empty row). False when it's already done or gone.
    @discardableResult
    public static func completeSet(_ setId: UUID, in settings: inout WorkoutSettings, now: Date = Date()) -> Bool {
        guard let session = settings.activeSession,
              let set = session.sets.first(where: { $0.id == setId }), set.completedAt == nil else { return false }
        let sets = session.sets.filter { $0.exerciseId == set.exerciseId }
        let index = sets.firstIndex { $0.id == setId } ?? 0
        let target = Self.target(at: index, sets: sets, exerciseId: set.exerciseId, session: session,
                                 routines: settings.routines + ExerciseCatalog.starterRoutines)
        settings.activeSession?.sets = WorkoutSessionLogic.complete(setId, in: session.sets, target: target, now: now)
        return true
    }

    private static func target(at index: Int, sets: [SetEntry], exerciseId: String, session: WorkoutSession,
                               routines: [Routine]) -> WorkoutSessionLogic.SetTarget {
        let item = WorkoutSessionLogic.routineItem(for: exerciseId, in: session, routines: routines)
        let targets = WorkoutSessionLogic.targets(for: sets, routineReps: item?.targetReps, routineWeight: item?.targetWeight)
        return index < targets.count ? targets[index] : WorkoutSessionLogic.SetTarget(reps: nil, weight: nil)
    }
}

/// "Done" from the lock screen, with no workout screen open: loads the
/// workouts document, ticks the set, saves with the optimistic version and
/// retries once on a conflict (the MotivationQuickLog pattern). An open
/// workout screen hears `didChange` and reloads.
public enum WorkoutQuickLog {
    public static let documentId = "workouts"
    public static let schemaVersion = 7
    public static let didChange = Notification.Name("WorkoutQuickLogDidChange")

    @discardableResult
    public static func completeSet(_ setId: UUID, store: WidgetDataStore, now: Date = Date()) async throws -> WorkoutSettings {
        var document = try await store.load(id: documentId)
        for attempt in 0..<2 {
            var settings = try document.map { try WidgetDocumentCodec.decode(WorkoutSettings.self, from: $0.payload) } ?? WorkoutSettings()
            guard WorkoutLivePlan.completeSet(setId, in: &settings, now: now) else { return settings }
            let next = WidgetDocument(version: document?.version ?? 0, payload: try WidgetDocumentCodec.encode(settings),
                                      schemaVersion: schemaVersion)
            do {
                _ = try await store.save(id: documentId, document: next)
                await MainActor.run { NotificationCenter.default.post(name: didChange, object: nil) }
                return settings
            } catch WidgetDataStoreError.conflict(let server) where attempt == 0 {
                if let server { document = server } else { document = try await store.load(id: documentId) }
            }
        }
        throw WidgetDataStoreError.conflict(server: nil)
    }

    /// The saved settings, for putting the lock screen back in step on launch.
    public static func load(store: WidgetDataStore) async -> WorkoutSettings? {
        guard let document = try? await store.load(id: documentId) else { return nil }
        return try? WidgetDocumentCodec.decode(WorkoutSettings.self, from: document.payload)
    }
}

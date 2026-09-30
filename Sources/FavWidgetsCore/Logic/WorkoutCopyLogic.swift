import Foundation

/// Turning someone else's shared workout into your own routine.
public enum WorkoutCopyLogic {

    public struct Copy: Equatable, Sendable {
        public let routine: Routine
        /// Custom exercises the viewer doesn't have yet, to add alongside
        public let newExercises: [Exercise]
    }

    /// The routine lines of a post: the shared routine when the poster's app
    /// sent one, else rebuilt from the exercise lines (older posts).
    public static func lines(of summary: WorkoutShareSummary) -> [WorkoutShareSummary.RoutineLine] {
        if let routine = summary.routine, !routine.isEmpty { return routine }
        return summary.exercises.map { line in
            WorkoutShareSummary.RoutineLine(exerciseId: nil, name: line.name, muscleGroup: "Other",
                                            sets: max(1, line.sets), reps: reps(inBestSet: line.bestSet) ?? 10, weight: nil)
        }
    }

    /// "135 lb × 5" → 5, "12 reps" → 12
    static func reps(inBestSet text: String) -> Int? {
        if let x = text.range(of: "×") {
            return Int(text[x.upperBound...].trimmingCharacters(in: .whitespaces))
        }
        return Int(text.components(separatedBy: " ").first ?? "")
    }

    /// A routine the viewer can start: built-in exercises keep their catalog
    /// id; anything else matches one of the viewer's exercises by name or
    /// becomes a new custom exercise. Weights are left out — the viewer's
    /// own last lift fills those in, not someone else's.
    public static func copy(_ summary: WorkoutShareSummary, named name: String, into settings: WorkoutSettings) -> Copy {
        var known = settings.allExercises
        var created: [Exercise] = []
        let builtInIds = Set(ExerciseCatalog.builtIn.map(\.id))

        func resolve(_ line: WorkoutShareSummary.RoutineLine) -> String {
            if let id = line.exerciseId, builtInIds.contains(id) { return id }
            let key = line.name.trimmingCharacters(in: .whitespaces).lowercased()
            if let match = known.first(where: { $0.name.lowercased() == key }) { return match.id }
            let exercise = Exercise(name: line.name, muscleGroup: line.muscleGroup)
            created.append(exercise)
            known.append(exercise)
            return exercise.id
        }

        var items: [RoutineItem] = []
        for line in lines(of: summary) {
            let id = resolve(line)
            guard !items.contains(where: { $0.exerciseId == id }) else { continue }
            items.append(RoutineItem(exerciseId: id, targetSets: max(1, min(line.sets, 10)), targetReps: max(1, line.reps)))
        }
        return Copy(routine: Routine(name: name, items: items), newExercises: created)
    }

    /// A name that doesn't clash with the viewer's routines: "Shoulders",
    /// else "Shoulders · Brittany", else "Shoulders · Brittany 2".
    public static func routineName(_ base: String, author: String, existing: [Routine]) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        let first = author.split(separator: " ").first.map(String.init) ?? author
        let withAuthor = "\(base) · \(first)"
        if !taken.contains(withAuthor.lowercased()) { return withAuthor }
        var n = 2
        while taken.contains("\(withAuthor) \(n)".lowercased()) { n += 1 }
        return "\(withAuthor) \(n)"
    }

    /// The viewer's routine that already holds this workout's exercises in
    /// this order — they copied it before — so the button starts it instead
    /// of making a duplicate.
    public static func existingCopy(of summary: WorkoutShareSummary, in settings: WorkoutSettings) -> Routine? {
        let wanted = copy(summary, named: "", into: settings)
        guard wanted.newExercises.isEmpty, !wanted.routine.items.isEmpty else { return nil }
        let ids = wanted.routine.items.map(\.exerciseId)
        return settings.routines.first { $0.items.map(\.exerciseId) == ids }
    }
}

import Foundation

/// Built-in exercises. Ids are stable strings so logs and PRs survive
/// renames.
public enum ExerciseCatalog {
    public static let builtIn: [Exercise] = [
        Exercise(id: "bench_press", name: "Bench Press", muscleGroup: "Chest"),
        Exercise(id: "incline_db_press", name: "Incline Dumbbell Press", muscleGroup: "Chest"),
        Exercise(id: "push_up", name: "Push-Up", muscleGroup: "Chest"),
        Exercise(id: "squat", name: "Squat", muscleGroup: "Legs"),
        Exercise(id: "leg_press", name: "Leg Press", muscleGroup: "Legs"),
        Exercise(id: "lunge", name: "Lunge", muscleGroup: "Legs"),
        Exercise(id: "romanian_deadlift", name: "Romanian Deadlift", muscleGroup: "Legs"),
        Exercise(id: "deadlift", name: "Deadlift", muscleGroup: "Back"),
        Exercise(id: "barbell_row", name: "Barbell Row", muscleGroup: "Back"),
        Exercise(id: "lat_pulldown", name: "Lat Pulldown", muscleGroup: "Back"),
        Exercise(id: "pull_up", name: "Pull-Up", muscleGroup: "Back"),
        Exercise(id: "overhead_press", name: "Overhead Press", muscleGroup: "Shoulders"),
        Exercise(id: "lateral_raise", name: "Lateral Raise", muscleGroup: "Shoulders"),
        Exercise(id: "bicep_curl", name: "Bicep Curl", muscleGroup: "Arms"),
        Exercise(id: "tricep_pushdown", name: "Tricep Pushdown", muscleGroup: "Arms"),
        Exercise(id: "plank", name: "Plank", muscleGroup: "Core"),
        Exercise(id: "hanging_leg_raise", name: "Hanging Leg Raise", muscleGroup: "Core")
    ]

    /// Starter routines offered until the user makes their own.
    public static let starterRoutines: [Routine] = [
        Routine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Push", items: [
            RoutineItem(exerciseId: "bench_press", targetSets: 4, targetReps: 8),
            RoutineItem(exerciseId: "overhead_press", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "incline_db_press", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "tricep_pushdown", targetSets: 3, targetReps: 12)
        ]),
        Routine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Pull", items: [
            RoutineItem(exerciseId: "deadlift", targetSets: 3, targetReps: 5),
            RoutineItem(exerciseId: "barbell_row", targetSets: 4, targetReps: 8),
            RoutineItem(exerciseId: "lat_pulldown", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "bicep_curl", targetSets: 3, targetReps: 12)
        ]),
        Routine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Legs", items: [
            RoutineItem(exerciseId: "squat", targetSets: 4, targetReps: 8),
            RoutineItem(exerciseId: "romanian_deadlift", targetSets: 3, targetReps: 10),
            RoutineItem(exerciseId: "leg_press", targetSets: 3, targetReps: 12),
            RoutineItem(exerciseId: "lunge", targetSets: 3, targetReps: 12)
        ])
    ]
}

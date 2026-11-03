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
        Exercise(id: "hanging_leg_raise", name: "Hanging Leg Raise", muscleGroup: "Core"),
        // Added for the example routines (2026-11-03). Add, never rename:
        // logs and PRs are keyed by these ids.
        Exercise(id: "db_bench_press", name: "Dumbbell Bench Press", muscleGroup: "Chest"),
        Exercise(id: "chest_fly", name: "Chest Fly", muscleGroup: "Chest"),
        Exercise(id: "dips", name: "Dips", muscleGroup: "Chest"),
        Exercise(id: "goblet_squat", name: "Goblet Squat", muscleGroup: "Legs"),
        Exercise(id: "bodyweight_squat", name: "Bodyweight Squat", muscleGroup: "Legs"),
        Exercise(id: "split_squat", name: "Bulgarian Split Squat", muscleGroup: "Legs"),
        Exercise(id: "hip_thrust", name: "Hip Thrust", muscleGroup: "Legs"),
        Exercise(id: "glute_bridge", name: "Glute Bridge", muscleGroup: "Legs"),
        Exercise(id: "leg_extension", name: "Leg Extension", muscleGroup: "Legs"),
        Exercise(id: "leg_curl", name: "Leg Curl", muscleGroup: "Legs"),
        Exercise(id: "calf_raise", name: "Calf Raise", muscleGroup: "Legs"),
        Exercise(id: "step_up", name: "Step-Up", muscleGroup: "Legs"),
        Exercise(id: "db_row", name: "Dumbbell Row", muscleGroup: "Back"),
        Exercise(id: "seated_cable_row", name: "Seated Cable Row", muscleGroup: "Back"),
        Exercise(id: "face_pull", name: "Face Pull", muscleGroup: "Shoulders"),
        Exercise(id: "db_shoulder_press", name: "Dumbbell Shoulder Press", muscleGroup: "Shoulders"),
        Exercise(id: "pike_push_up", name: "Pike Push-Up", muscleGroup: "Shoulders"),
        Exercise(id: "hammer_curl", name: "Hammer Curl", muscleGroup: "Arms"),
        Exercise(id: "skull_crusher", name: "Skull Crusher", muscleGroup: "Arms"),
        Exercise(id: "crunch", name: "Crunch", muscleGroup: "Core"),
        Exercise(id: "russian_twist", name: "Russian Twist", muscleGroup: "Core"),
        Exercise(id: "dead_bug", name: "Dead Bug", muscleGroup: "Core"),
        Exercise(id: "mountain_climber", name: "Mountain Climber", muscleGroup: "Cardio"),
        Exercise(id: "burpee", name: "Burpee", muscleGroup: "Cardio"),
        Exercise(id: "jumping_jack", name: "Jumping Jack", muscleGroup: "Cardio")
    ]

    /// Every example routine (see `WorkoutTemplates`). Routines are looked
    /// up by id for a workout in progress, so these stay findable.
    public static var starterRoutines: [Routine] { WorkoutTemplates.all.map(\.routine) }
}

import Foundation

/// Example routines, so nobody starts from a blank page (Wes, 2026-11-03).
/// Shown on the Workouts start page under their own heading, always, and
/// suggested by "Pick one for me". Starting one runs it as is; "Save to my
/// routines" copies it with a fresh id so it can be changed.
///
/// Ids are fixed: a workout in progress finds its routine by id (the lock
/// screen, the next exercise). Push/Pull/Legs keep the ids they had as the
/// original three starters. Add templates, never renumber them.
public struct WorkoutTemplate: Identifiable, Equatable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case starting, strength, muscle, home, core

        public var title: String {
            switch self {
            case .starting: return "Just starting"
            case .strength: return "Get stronger"
            case .muscle: return "Build muscle"
            case .home: return "Dumbbells & home"
            case .core: return "Core & cardio"
            }
        }
    }

    public enum Level: String, Sendable {
        case beginner, intermediate

        public var label: String { self == .beginner ? "Beginner" : "Intermediate" }
    }

    public enum Equipment: String, CaseIterable, Sendable {
        case gym, dumbbells, none

        public var label: String {
            switch self {
            case .gym: return "Gym"
            case .dumbbells: return "Dumbbells"
            case .none: return "No equipment"
            }
        }
    }

    public let routine: Routine
    public let group: Group
    public let level: Level
    public let equipment: Equipment
    /// What it's for and how often, in one or two short sentences
    public let blurb: String

    public var id: UUID { routine.id }
    public var name: String { routine.name }
    public var totalSets: Int { routine.items.reduce(0) { $0 + max(1, $1.targetSets) } }

    /// About how long it takes: two minutes a set (the set plus rest) and
    /// five to warm up, to the nearest five minutes
    public var minutes: Int {
        let raw = totalSets * 2 + 5
        return max(10, Int((Double(raw) / 5).rounded()) * 5)
    }
}

public enum WorkoutTemplates {
    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private static func item(_ exerciseId: String, _ sets: Int, _ reps: Int) -> RoutineItem {
        RoutineItem(exerciseId: exerciseId, targetSets: sets, targetReps: reps)
    }

    private static func template(_ n: Int, _ name: String, _ group: WorkoutTemplate.Group, _ level: WorkoutTemplate.Level,
                                 _ equipment: WorkoutTemplate.Equipment, _ blurb: String, _ items: [RoutineItem]) -> WorkoutTemplate {
        WorkoutTemplate(routine: Routine(id: id(n), name: name, items: items), group: group, level: level,
                        equipment: equipment, blurb: blurb)
    }

    public static let all: [WorkoutTemplate] = [
        // The original three starters: same ids, same exercises
        template(1, "Push", .muscle, .intermediate, .gym, "Chest, shoulders and triceps. Pair with Pull and Legs, 3–6 days a week.", [
            item("bench_press", 4, 8), item("overhead_press", 3, 10), item("incline_db_press", 3, 10), item("tricep_pushdown", 3, 12)
        ]),
        template(2, "Pull", .muscle, .intermediate, .gym, "Back and biceps. Pair with Push and Legs.", [
            item("deadlift", 3, 5), item("barbell_row", 4, 8), item("lat_pulldown", 3, 10), item("bicep_curl", 3, 12)
        ]),
        template(3, "Legs", .muscle, .intermediate, .gym, "Quads, hamstrings and glutes. Pair with Push and Pull.", [
            item("squat", 4, 8), item("romanian_deadlift", 3, 10), item("leg_press", 3, 12), item("lunge", 3, 12)
        ]),

        template(10, "Full Body A", .starting, .beginner, .gym, "Your first gym routine. Alternate with Full Body B, 3 days a week.", [
            item("goblet_squat", 3, 10), item("db_bench_press", 3, 10), item("lat_pulldown", 3, 10),
            item("glute_bridge", 3, 12), item("dead_bug", 2, 10)
        ]),
        template(11, "Full Body B", .starting, .beginner, .gym, "Every muscle, nothing complicated. Alternate with Full Body A.", [
            item("leg_press", 3, 12), item("db_shoulder_press", 3, 10), item("seated_cable_row", 3, 10),
            item("leg_curl", 2, 12), item("crunch", 2, 15)
        ]),

        template(20, "5×5 Workout A", .strength, .intermediate, .gym, "Classic strength: five sets of five. Alternate A and B, 3 days a week, adding a little weight each time.", [
            item("squat", 5, 5), item("bench_press", 5, 5), item("barbell_row", 5, 5)
        ]),
        template(21, "5×5 Workout B", .strength, .intermediate, .gym, "The other half of 5×5. One heavy set of deadlifts.", [
            item("squat", 5, 5), item("overhead_press", 5, 5), item("deadlift", 1, 5)
        ]),
        template(22, "Upper Body", .strength, .intermediate, .gym, "Everything above the waist. Alternate with Lower Body, 4 days a week.", [
            item("bench_press", 4, 8), item("barbell_row", 4, 8), item("overhead_press", 3, 10),
            item("lat_pulldown", 3, 10), item("bicep_curl", 2, 12), item("tricep_pushdown", 2, 12)
        ]),
        template(23, "Lower Body", .strength, .intermediate, .gym, "Legs and glutes. Alternate with Upper Body.", [
            item("squat", 4, 8), item("romanian_deadlift", 3, 10), item("leg_curl", 3, 12),
            item("leg_extension", 3, 12), item("calf_raise", 3, 15)
        ]),

        template(30, "Glutes & Legs", .muscle, .beginner, .gym, "Hip thrusts first while you're fresh. Once or twice a week.", [
            item("hip_thrust", 4, 10), item("split_squat", 3, 10), item("romanian_deadlift", 3, 10),
            item("leg_curl", 3, 12), item("glute_bridge", 2, 15)
        ]),
        template(31, "Chest & Back", .muscle, .intermediate, .gym, "Push and pull in one session, supersets welcome.", [
            item("bench_press", 4, 8), item("seated_cable_row", 4, 10), item("incline_db_press", 3, 10),
            item("lat_pulldown", 3, 10), item("chest_fly", 2, 12), item("face_pull", 2, 15)
        ]),
        template(32, "Arms & Shoulders", .muscle, .beginner, .gym, "A lighter day: shoulders, biceps and triceps.", [
            item("db_shoulder_press", 3, 10), item("lateral_raise", 3, 15), item("bicep_curl", 3, 12),
            item("skull_crusher", 3, 12), item("hammer_curl", 2, 12), item("dips", 2, 10)
        ]),

        template(40, "Dumbbell Full Body", .home, .beginner, .dumbbells, "Just a pair of dumbbells. 3 days a week.", [
            item("goblet_squat", 3, 12), item("db_bench_press", 3, 10), item("db_row", 3, 10),
            item("db_shoulder_press", 3, 10), item("step_up", 2, 10), item("hammer_curl", 2, 12)
        ]),
        template(41, "No-Equipment Full Body", .home, .beginner, .none, "Living-room friendly. No gym, no gear.", [
            item("bodyweight_squat", 3, 15), item("push_up", 3, 10), item("lunge", 3, 10),
            item("glute_bridge", 3, 15), item("pike_push_up", 2, 8), item("dead_bug", 2, 10)
        ]),
        template(42, "Home Sweat", .core, .beginner, .none, "Quick and breathless: go round the list, short rests.", [
            item("jumping_jack", 3, 30), item("bodyweight_squat", 3, 20), item("mountain_climber", 3, 20),
            item("push_up", 3, 10), item("burpee", 3, 8)
        ]),
        template(43, "Core Crusher", .core, .beginner, .none, "Abs and core in about 20 minutes. Add it after any workout.", [
            item("dead_bug", 3, 10), item("crunch", 3, 15), item("russian_twist", 3, 20), item("mountain_climber", 2, 20)
        ])
    ]

    public static func template(id: UUID) -> WorkoutTemplate? {
        all.first { $0.id == id }
    }

    /// The groups in order, each with its templates (empty groups left out)
    public static var grouped: [(group: WorkoutTemplate.Group, templates: [WorkoutTemplate])] {
        WorkoutTemplate.Group.allCases.compactMap { group in
            let list = all.filter { $0.group == group }
            return list.isEmpty ? nil : (group, list)
        }
    }

    // MARK: - Pick one for me

    public struct Recommendation: Equatable, Sendable {
        public let templates: [WorkoutTemplate]
        /// How to use them over a week
        public let plan: String
    }

    /// Two quick answers → the routines to start with and how to run them
    public static func recommend(equipment: WorkoutTemplate.Equipment, level: WorkoutTemplate.Level) -> Recommendation {
        func pick(_ ids: [Int]) -> [WorkoutTemplate] { ids.compactMap { template(id: id($0)) } }
        switch (equipment, level) {
        case (.none, _):
            return Recommendation(templates: pick([41, 42, 43]),
                                  plan: "Do No-Equipment Full Body 3 days a week. Add Home Sweat or Core Crusher on a day in between if you want more.")
        case (.dumbbells, .beginner):
            return Recommendation(templates: pick([40, 43]),
                                  plan: "Do Dumbbell Full Body 3 days a week, with a rest day in between. Finish with Core Crusher when you have 10 extra minutes.")
        case (.dumbbells, .intermediate):
            return Recommendation(templates: pick([40, 41, 43]),
                                  plan: "Alternate Dumbbell Full Body and No-Equipment Full Body, 4 days a week. Use heavier dumbbells as the reps get easy.")
        case (.gym, .beginner):
            return Recommendation(templates: pick([10, 11]),
                                  plan: "Alternate Full Body A and B, 3 days a week (say Monday, Wednesday, Friday). After a month or two, try 5×5.")
        case (.gym, .intermediate):
            return Recommendation(templates: pick([20, 21, 1, 2, 3]),
                                  plan: "For strength: alternate 5×5 A and B, 3 days a week. For size: Push, Pull, Legs in a loop, 3–6 days a week.")
        }
    }
}

/// One line of form for each built-in exercise, shown in the routine
/// preview so a beginner knows what good looks like.
public enum ExerciseTips {
    public static let startLight = "Start light. Pick a weight you could lift 2–3 more times at the end of each set, then add a little next time."

    public static func cue(for exerciseId: String) -> String? { cues[exerciseId] }

    private static let cues: [String: String] = [
        "bench_press": "Feet flat, shoulder blades squeezed, lower the bar to mid-chest.",
        "incline_db_press": "Bench at 30–45°, press up and slightly in.",
        "push_up": "Body in one straight line; chest nearly to the floor.",
        "squat": "Chest up, knees track over toes, hips to at least knee height.",
        "leg_press": "Lower until knees are at 90°; don't lock them at the top.",
        "lunge": "Long step, back knee toward the floor, front knee over the ankle.",
        "romanian_deadlift": "Soft knees, push hips back, bar slides down the thighs.",
        "deadlift": "Bar over mid-foot, flat back, push the floor away.",
        "barbell_row": "Hinge forward, pull the bar to your lower ribs.",
        "lat_pulldown": "Pull the bar to your upper chest, elbows down and back.",
        "pull_up": "Start from a dead hang, chin over the bar, lower slowly.",
        "overhead_press": "Squeeze glutes, press straight up, head through at the top.",
        "lateral_raise": "Slight bend in the elbows, raise to shoulder height, no swinging.",
        "bicep_curl": "Elbows pinned at your sides; lower all the way down.",
        "tricep_pushdown": "Elbows tucked; straighten the arms fully.",
        "plank": "Squeeze glutes and abs; don't let the hips sag.",
        "hanging_leg_raise": "No swinging; curl the pelvis up, not just the legs.",
        "db_bench_press": "Dumbbells over the chest, lower to the sides with control.",
        "chest_fly": "Wide arc with a slight elbow bend; feel the stretch, then hug.",
        "dips": "Lean slightly forward, lower until upper arms are level.",
        "goblet_squat": "Hold the dumbbell at your chest, sit between your heels.",
        "bodyweight_squat": "Arms forward for balance, sit back and down.",
        "split_squat": "Back foot on a bench, drop straight down on the front leg.",
        "hip_thrust": "Upper back on a bench, drive through heels, squeeze at the top.",
        "glute_bridge": "Feet close to your hips, lift until knees, hips and shoulders line up.",
        "leg_extension": "Pause at the top; lower slowly.",
        "leg_curl": "Curl all the way; don't let the hips lift.",
        "calf_raise": "Full stretch at the bottom, pause high on your toes.",
        "step_up": "Whole foot on the step; push through the heel.",
        "db_row": "One hand on a bench, pull the dumbbell to your hip.",
        "seated_cable_row": "Sit tall, pull to your belly, squeeze the shoulder blades.",
        "face_pull": "Rope to your forehead, elbows high, pull the rope apart.",
        "db_shoulder_press": "Start at ear height, press up without arching your back.",
        "pike_push_up": "Hips high in an upside-down V, head toward the floor.",
        "hammer_curl": "Palms facing each other; elbows still.",
        "skull_crusher": "Elbows point up; lower the weight toward your forehead.",
        "crunch": "Lift the shoulders, not the neck; breathe out on the way up.",
        "russian_twist": "Lean back a little, rotate the chest, not just the arms. Each side counts as one.",
        "dead_bug": "Low back pressed down; opposite arm and leg reach out slowly.",
        "mountain_climber": "Plank position, drive knees to chest quickly. Each leg counts as one.",
        "burpee": "Squat, jump the feet back, push-up optional, jump up.",
        "jumping_jack": "Light on your feet; arms all the way overhead."
    ]
}

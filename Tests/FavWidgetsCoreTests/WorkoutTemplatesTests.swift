import Foundation
import Testing
@testable import FavWidgetsCore

@Suite struct WorkoutTemplatesTests {
    @Test func everyTemplateIsComplete() {
        let builtIn = Set(ExerciseCatalog.builtIn.map(\.id))
        for template in WorkoutTemplates.all {
            #expect(!template.routine.items.isEmpty, "\(template.name) is empty")
            for item in template.routine.items {
                #expect(builtIn.contains(item.exerciseId), "\(template.name): unknown exercise \(item.exerciseId)")
                #expect(item.targetSets > 0 && item.targetReps > 0)
            }
            #expect(!template.blurb.isEmpty)
        }
    }

    @Test func idsAreUniqueAndTheOriginalStartersKeepTheirs() {
        let ids = WorkoutTemplates.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        // A workout in progress finds its routine by these
        #expect(WorkoutTemplates.template(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)?.name == "Push")
        #expect(WorkoutTemplates.template(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)?.name == "Pull")
        #expect(WorkoutTemplates.template(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)?.name == "Legs")
        #expect(ExerciseCatalog.starterRoutines.count == WorkoutTemplates.all.count)
    }

    @Test func exerciseIdsAreNeverDuplicated() {
        let ids = ExerciseCatalog.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyBuiltInExerciseHasAFormCue() {
        for exercise in ExerciseCatalog.builtIn {
            #expect(ExerciseTips.cue(for: exercise.id) != nil, "no cue for \(exercise.id)")
        }
    }

    @Test func minutesAreAboutTwoASetPlusWarmUp() {
        let fiveByFiveB = WorkoutTemplates.all.first { $0.name == "5×5 Workout B" }!
        #expect(fiveByFiveB.totalSets == 11)
        #expect(fiveByFiveB.minutes == 25)
        #expect(WorkoutTemplates.all.allSatisfy { $0.minutes % 5 == 0 && $0.minutes >= 10 })
    }

    @Test func recommendationsFitTheEquipment() {
        for level in [WorkoutTemplate.Level.beginner, .intermediate] {
            let home = WorkoutTemplates.recommend(equipment: .none, level: level)
            #expect(!home.templates.isEmpty)
            #expect(home.templates.allSatisfy { $0.equipment == .none })
            let dumbbells = WorkoutTemplates.recommend(equipment: .dumbbells, level: level)
            #expect(dumbbells.templates.allSatisfy { $0.equipment != .gym })
        }
        let newToTheGym = WorkoutTemplates.recommend(equipment: .gym, level: .beginner)
        #expect(newToTheGym.templates.map(\.name) == ["Full Body A", "Full Body B"])
        #expect(WorkoutTemplates.recommend(equipment: .gym, level: .intermediate).templates.first?.name == "5×5 Workout A")
    }

    @Test func groupsListEveryTemplateOnce() {
        let grouped = WorkoutTemplates.grouped.flatMap(\.templates).map(\.id)
        #expect(grouped.count == WorkoutTemplates.all.count)
        #expect(Set(grouped) == Set(WorkoutTemplates.all.map(\.id)))
    }
}

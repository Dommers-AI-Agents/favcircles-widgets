import Testing
import Foundation
@testable import FavWidgetsCore

struct WorkoutCardioAndShareTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    @Test func oldDocumentsDecodeWithTheNewFieldsDefaulted() throws {
        // A settings doc and a month shard written before profile/cardio/images existed.
        let settingsJSON = #"{"unit":"lb","restTimerSeconds":90,"autoRestTimer":true,"customExercises":[{"id":"x","name":"Cable Fly","muscleGroup":"Chest"}],"routines":[],"prsByExercise":{}}"#
        let settings = try JSONDecoder().decode(WorkoutSettings.self, from: Data(settingsJSON.utf8))
        #expect(settings.profile.isEmpty)
        #expect(settings.exerciseImages.isEmpty)
        #expect(!settings.shareWithInnerCircle)
        #expect(settings.customExercises.first?.imageUrl == nil)
        #expect(settings.imageURL(for: "x") == nil)

        let monthJSON = #"{"sessions":[{"id":"6E1F2C8E-0000-4000-8000-000000000001","name":"Push","startedAt":700000000,"endedAt":700003600,"sets":[{"id":"6E1F2C8E-0000-4000-8000-000000000002","exerciseId":"bench_press","reps":5,"weight":100,"isWarmup":false,"completedAt":700000100}]}]}"#
        let month = try JSONDecoder().decode(WorkoutMonth.self, from: Data(monthJSON.utf8))
        #expect(month.sessions.first?.cardio.isEmpty == true)
        #expect(month.sessions.first?.exerciseCount == 1)
    }

    @Test func caloriesNeedAWeightAndScaleWithEffort() {
        #expect(WorkoutCardioLogic.estimatedCalories(kind: .treadmill, intensity: .moderate, minutes: 30, weightKg: nil) == nil)
        let easy = WorkoutCardioLogic.estimatedCalories(kind: .cycle, intensity: .easy, minutes: 30, weightKg: 80)!
        let hard = WorkoutCardioLogic.estimatedCalories(kind: .cycle, intensity: .hard, minutes: 30, weightKg: 80)!
        #expect(easy == 160) // 4.0 × 80 × 0.5
        #expect(hard == 400)
        let typed = CardioEntry(kind: .stepper, minutes: 20, calories: 250)
        #expect(WorkoutCardioLogic.calories(for: typed, weightKg: 80) == 250)
        #expect(WorkoutCardioLogic.line(for: typed, distanceUnit: "mi", weightKg: 80) == "20 min · 250 kcal")
        let estimated = CardioEntry(kind: .treadmill, minutes: 20, distance: 1.5)
        #expect(WorkoutCardioLogic.line(for: estimated, distanceUnit: "mi", weightKg: 80) == "20 min · 1.5 mi · 133 kcal est.")
    }

    @Test func unitConversions() {
        #expect(abs(WorkoutCardioLogic.kg(fromLb: 172) - 78.02) < 0.01)
        #expect(abs(WorkoutCardioLogic.lb(fromKg: 78) - 171.96) < 0.01)
        #expect(abs(WorkoutCardioLogic.cm(feet: 5, inches: 11) - 180.34) < 0.01)
        #expect(WorkoutCardioLogic.feetInches(fromCm: 180.34) == (5, 11))
        #expect(WorkoutCardioLogic.heightText(180.34, unit: .lb) == "5′11″")
        #expect(WorkoutCardioLogic.heightText(180.34, unit: .kg) == "180 cm")
        #expect(WorkoutCardioLogic.weightText(78, unit: .lb) == "172 lb")
    }

    @Test func finishKeepsCardioAndStampsIt() {
        let start = Self.cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 7))!
        var session = WorkoutSession(name: "Cardio day", startedAt: start)
        session.cardio = [CardioEntry(kind: .stepper, minutes: 15), CardioEntry(kind: .cycle)]
        #expect(WorkoutSessionLogic.hasUserData(session))
        let result = WorkoutSessionLogic.finish(session, existingRecords: [:], at: start.addingTimeInterval(1200))
        #expect(result.session.cardio.count == 1)
        #expect(result.session.cardio.first?.completedAt != nil)
        #expect(result.session.cardioMinutes == 15)
        #expect(!WorkoutSessionLogic.hasUserData(WorkoutSession(name: "Empty", cardio: [CardioEntry(kind: .rower)])))
    }

    @Test func shareSummaryAndText() {
        let start = Self.cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 7))!
        let done = start.addingTimeInterval(60)
        var session = WorkoutSession(name: "Push", startedAt: start, endedAt: start.addingTimeInterval(2700), sets: [
            SetEntry(exerciseId: "bench_press", reps: 8, weight: 135, isWarmup: true, completedAt: done),
            SetEntry(exerciseId: "bench_press", reps: 5, weight: 185, completedAt: done),
            SetEntry(exerciseId: "bench_press", reps: 5, weight: 195, completedAt: done),
            SetEntry(exerciseId: "push_up", reps: 20, weight: 0, completedAt: done),
            SetEntry(exerciseId: "squat", reps: 0, weight: 0)
        ])
        session.cardio = [CardioEntry(kind: .treadmill, minutes: 10, distance: 1, completedAt: done)]
        let pr = PersonalRecord(weight: 195, reps: 5, estimatedOneRM: 227, date: done, sessionId: session.id)
        let summary = WorkoutShareSummary.make(session: session, newRecords: ["bench_press": pr], unit: .lb, weightKg: 80) { id in
            id == "bench_press" ? "Bench Press" : id == "push_up" ? "Push-Up" : "?"
        }
        #expect(summary.exercises.map(\.name) == ["Bench Press", "Push-Up"])
        #expect(summary.exercises[0].bestSet == "195 lb × 5")
        #expect(summary.exercises[0].sets == 2) // warm-up not counted
        #expect(summary.exercises[0].isPR)
        #expect(summary.exercises[1].bestSet == "20 reps")
        #expect(summary.cardio.first?.detail == "10 min · 1 mi · 67 kcal est.")
        #expect(summary.completedSets == 4)
        #expect(summary.prCount == 1)
        let text = summary.shareText(calendar: Self.cal)
        #expect(text.hasPrefix("Push · Sep 19, 2026\n45 min · 2 exercises · 4 sets · 10 min cardio · 1 PR\n• Bench Press: 195 lb × 5 🏆 (2 sets)\n• Push-Up: 20 reps (1 set)\n• Treadmill: 10 min · 1 mi · 67 kcal est.\nLogged with FavCircles"))
        // Round-trips through JSON for the Inner Circle post.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(summary)
        let back = try! WidgetJSON.decode(WorkoutShareSummary.self, from: data)
        #expect(back == summary)
    }
}

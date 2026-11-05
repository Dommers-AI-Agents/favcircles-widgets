import Foundation
import Testing
@testable import FavWidgetsCore

struct SleepBedtimeTests {
    @Test func oneRepeatingTriggerPerChosenNight() {
        let triggers = SleepBedtimePlan.triggers(SleepBedtime(enabled: true, minutes: 22 * 60 + 30, weekdays: [6, 2, 2, 9]))
        #expect(triggers.map(\.weekday) == [2, 6])
        #expect(triggers.allSatisfy { $0.hour == 22 && $0.minute == 30 })
        #expect(SleepBedtimePlan.triggers(SleepBedtime(enabled: false)).isEmpty)
    }

    @Test func playsTheChosenMixElseTheLastOne() {
        let saved = SleepMix(id: "mine", name: "My rain", levels: ["rain": 0.7])
        var settings = SleepSoundsSettings(mixes: [saved], lastLevels: ["ocean": 0.5], lastMixName: "Ocean")
        #expect(SleepBedtimePlan.mix(for: SleepBedtime(mixId: "mine"), in: settings).name == "My rain")
        #expect(SleepBedtimePlan.mix(for: SleepBedtime(mixId: "deleted"), in: settings).name == "Ocean")
        #expect(SleepBedtimePlan.mix(for: nil, in: settings).name == "Ocean")
        settings.lastLevels = [:]
        #expect(SleepBedtimePlan.mix(for: nil, in: settings).name == SleepMix.builtIns[0].name)
    }

    @Test func daysReadLikePeopleSayThem() {
        #expect(SleepBedtime().weekdays == SleepBedtime.weekdaysOnly)   // Wes asked for weekdays
        #expect(SleepBedtimePlan.daysLabel(SleepBedtime.weekdaysOnly) == "Weekdays")
        #expect(SleepBedtimePlan.daysLabel(SleepBedtime.weeknights) == "Sunday to Thursday")
        #expect(SleepBedtimePlan.daysLabel(SleepBedtime.everyDay) == "Every night")
        #expect(SleepBedtimePlan.daysLabel([]) == "No days")
    }

    @Test func oldSettingsStillDecode() throws {
        let json = #"{"mixes":[],"lastLevels":{},"timerMinutes":45,"masterVolume":0.8}"#
        let settings = try JSONDecoder().decode(SleepSoundsSettings.self, from: Data(json.utf8))
        #expect(settings.bedtime == nil)
    }
}

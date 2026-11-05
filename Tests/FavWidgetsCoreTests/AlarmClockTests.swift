import Foundation
import Testing
@testable import FavWidgetsCore

/// Wake Up (Wes, 2026-11-05): when alarms ring, the words for them, pasted
/// station links, and what the phone is asked to set.
struct AlarmClockTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    /// Thursday, November 5, 2026 at `hour:minute`
    private func thu(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: hour, minute: minute))!
    }

    // MARK: Next ring

    @Test func onceRingsTodayIfStillAheadElseTomorrow() {
        let alarm = WakeAlarm(minutes: 7 * 60 + 30)
        #expect(AlarmClockPlan.nextRing(alarm, after: thu(6), calendar: calendar) == thu(7, 30))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: thu(7, 30))!
        #expect(AlarmClockPlan.nextRing(alarm, after: thu(8), calendar: calendar) == tomorrow)
    }

    @Test func weekdaysSkipTheWeekendAndOffNeverRings() {
        let weekdays = WakeAlarm(minutes: 6 * 60, days: [2, 3, 4, 5, 6])
        // Friday evening → Monday 6:00
        let friday = calendar.date(byAdding: .day, value: 1, to: thu(20))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 6))!
        #expect(AlarmClockPlan.nextRing(weekdays, after: friday, calendar: calendar) == monday)
        var off = weekdays
        off.enabled = false
        #expect(AlarmClockPlan.nextRing(off, after: friday, calendar: calendar) == nil)
    }

    @Test func soonestOfSeveral() {
        let a = WakeAlarm(id: "a", minutes: 9 * 60)
        let b = WakeAlarm(id: "b", minutes: 6 * 60 + 45)
        #expect(AlarmClockPlan.next([a, b], after: thu(1), calendar: calendar)?.alarm.id == "b")
        #expect(AlarmClockPlan.next([], after: thu(1), calendar: calendar) == nil)
    }

    // MARK: Words

    @Test func ringsInWords() {
        #expect(AlarmClockPlan.ringsIn(thu(7, 23), from: thu(0)) == "Rings in 7 hr 23 min")
        #expect(AlarmClockPlan.ringsIn(thu(0, 45), from: thu(0)) == "Rings in 45 min")
        #expect(AlarmClockPlan.ringsIn(thu(2), from: thu(0)) == "Rings in 2 hr")
        #expect(AlarmClockPlan.ringsIn(thu(0, 0).addingTimeInterval(20), from: thu(0)) == "Rings in under a minute")
    }

    @Test func daysWords() {
        #expect(AlarmClockPlan.daysText([], calendar: calendar) == "Once")
        #expect(AlarmClockPlan.daysText(Array(1...7), calendar: calendar) == "Every day")
        #expect(AlarmClockPlan.daysText([2, 3, 4, 5, 6], calendar: calendar) == "Weekdays")
        #expect(AlarmClockPlan.daysText([7, 1], calendar: calendar) == "Weekends")
        #expect(AlarmClockPlan.daysText([1, 2, 4], calendar: calendar) == "Mon, Wed, Sun")
        // iOS formats with a narrow no-break space before AM
        #expect(AlarmClockPlan.timeText(7 * 60 + 5, calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " ") == "7:05 AM")
    }

    @Test func titleIsTheLabelThenTheStation() {
        let station = MusicStation(name: "Morning Mix", link: "pandora.com/station/1")
        #expect(AlarmClockPlan.title(WakeAlarm(label: " Gym "), station: station) == "Gym")
        #expect(AlarmClockPlan.title(WakeAlarm(), station: station) == "Wake up to Morning Mix")
        #expect(AlarmClockPlan.title(WakeAlarm(), station: nil) == "Wake up")
    }

    // MARK: Links

    @Test func pastedLinksBecomeURLsAndKnowTheirApp() {
        #expect(MusicLink.url(from: "https://www.pandora.com/station/play/123")?.host == "www.pandora.com")
        #expect(MusicLink.url(from: "pandora.app.link/abc")?.absoluteString == "https://pandora.app.link/abc")
        #expect(MusicLink.url(from: "Listen to Morning Mix on Pandora https://pandora.app.link/xyz")?.absoluteString
                == "https://pandora.app.link/xyz")
        #expect(MusicLink.url(from: "spotify:playlist:37i9dQZF1DX")?.scheme == "spotify")
        #expect(MusicLink.url(from: "not a link") == nil)
        #expect(MusicLink.url(from: "") == nil)
        #expect(MusicLink.url(from: "https://nohost") == nil)

        #expect(MusicLink.service(of: "https://pandora.app.link/abc") == .pandora)
        #expect(MusicLink.service(of: "https://open.spotify.com/playlist/1") == .spotify)
        #expect(MusicLink.service(of: "https://music.apple.com/us/station/x") == .appleMusic)
        #expect(MusicLink.service(of: "https://music.youtube.com/watch?v=1") == .youtubeMusic)
        #expect(MusicLink.service(of: "https://example.com/radio") == .other)
    }

    // MARK: What the phone sets

    @Test func specsCarryOnlyAlarmsThatAreOnWithTheirStation() {
        let station = MusicStation(id: "s", name: "Morning Mix", link: "https://pandora.app.link/abc")
        let settings = AlarmClockSettings(alarms: [
            WakeAlarm(id: "on", minutes: 6 * 60 + 30, days: [2, 3], stationId: "s", snoozeMinutes: 10),
            WakeAlarm(id: "off", enabled: false),
            WakeAlarm(id: "gone-station", stationId: "deleted")
        ], stations: [station])
        let specs = AlarmClockPlan.specs(settings)
        #expect(specs.map(\.id) == ["on", "gone-station"])
        #expect(specs[0] == WidgetAlarmSpec(id: "on", hour: 6, minute: 30, weekdays: [2, 3], title: "Wake up to Morning Mix",
                                            stationName: "Morning Mix", stationURL: station.url, snoozeMinutes: 10))
        #expect(specs[1].stationURL == nil && specs[1].title == "Wake up")
    }

    @Test func aOneTimeAlarmSwitchesOffAfterItRings() {
        var settings = AlarmClockSettings(alarms: [
            WakeAlarm(id: "rang", onceAt: thu(7)),
            WakeAlarm(id: "later", onceAt: thu(9)),
            WakeAlarm(id: "repeats", days: [5], onceAt: thu(7))
        ])
        #expect(AlarmClockPlan.expireRungOnce(&settings, now: thu(8)) == ["rang"])
        #expect(settings.alarms.map(\.enabled) == [false, true, true])
        #expect(settings.alarms[0].onceAt == nil)
        #expect(AlarmClockPlan.expireRungOnce(&settings, now: thu(8)).isEmpty)
    }

    @Test func settingsRoundTripAndTolerateOldShapes() throws {
        let settings = AlarmClockSettings(alarms: [WakeAlarm(id: "a", stationId: "s")], stations: [MusicStation(id: "s", name: "x", link: "y.com")])
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AlarmClockSettings.self, from: data) == settings)
    }
}

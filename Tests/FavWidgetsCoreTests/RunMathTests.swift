import Testing
import Foundation
@testable import FavWidgetsCore

struct RunMathTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    /// A fix `meters` north of the start, `seconds` in.
    private func fix(_ meters: Double, _ seconds: Double, accuracy: Double = 5) -> RunFix {
        RunFix(latitude: 35.2 + meters / 111_195, longitude: -80.85, time: t0.addingTimeInterval(seconds), accuracy: accuracy)
    }

    /// A steady run: one fix every 5 s at `speed` m/s.
    private func steady(meters: Double, speed: Double) -> RunTrack {
        var track = RunTrack(startedAt: t0)
        var m = 0.0, s = 0.0
        while m <= meters { track.add(fix(m, s)); m += speed * 5; s += 5 }
        return track
    }

    @Test func distanceAndTimeOfASteadyRun() {
        let track = steady(meters: 3218.7, speed: 3.0)                 // ~2 mi at 3 m/s
        #expect(abs(track.distance - 3218.7) < 20)
        #expect(abs(track.movingSeconds(at: track.points.last!.time) - track.distance / 3.0) < 6)
    }

    @Test func badFixesAndJumpsDoNotAddDistance() {
        var track = RunTrack(startedAt: t0)
        track.add(fix(0, 0))
        let poorFix = track.add(fix(15, 5, accuracy: 80)); #expect(!poorFix)                  // poor accuracy
        let jump = track.add(fix(500, 10)); #expect(!jump)                               // 50 m/s jump
        let jitter = track.add(fix(1, 15)); #expect(!jitter)                                 // jitter while standing
        let realStep = track.add(fix(15, 20)); #expect(realStep)
        #expect(abs(track.distance - 15) < 0.5)
    }

    @Test func pausingStopsTheClockAndTheGapIsNotCounted() {
        var track = RunTrack(startedAt: t0)
        track.add(fix(0, 0)); track.add(fix(300, 100))
        track.pause(at: t0.addingTimeInterval(100))
        let whilePaused = track.add(fix(400, 200)); #expect(!whilePaused)                              // ignored while paused
        track.resume(at: t0.addingTimeInterval(400))
        track.add(fix(2000, 405))                                       // first fix of the new segment: no distance
        track.add(fix(2300, 505))
        #expect(abs(track.distance - 600) < 1)
        #expect(abs(track.movingSeconds(at: t0.addingTimeInterval(505)) - 205) < 0.01)
    }

    @Test func splitsAndBestEfforts() {
        // 1 km at 4:00/km, then 1 km at 5:00/km
        let samples = [RunSample(meters: 0, seconds: 0), RunSample(meters: 1000, seconds: 240), RunSample(meters: 2000, seconds: 540)]
        #expect(RunMath.splits(samples, unit: .kilometers) == [240, 300])
        #expect(RunMath.bestEffort(samples, meters: 1000) == 240)
        #expect(RunMath.bestEffort(samples, meters: 5000) == nil)
        #expect(RunMath.paceText(RunMath.pace(seconds: 540, meters: 2000, unit: .kilometers)) == "4:30")
        #expect(RunMath.clock(3725) == "1:02:05")
    }

    @Test func routeSurvivesSimplifyAndEncoding() {
        var pts: [(Double, Double)] = []
        for i in 0..<2000 {
            let lat: Double = 35.2 + Double(i) * 0.00005
            let lon: Double = -80.85 + sin(Double(i) / 50) * 0.001
            pts.append((lat, lon))
        }
        let small = RunGeo.simplify(pts, maxPoints: 600)
        #expect(small.count <= 600 && small.count > 20)
        let endsKept = small.first!.0 == pts.first!.0 && small.last!.0 == pts.last!.0
        #expect(endsKept)
        let decoded = RunGeo.decode(RunGeo.encode(small))
        #expect(decoded.count == small.count)
        var maxErr = 0.0
        for (d, o) in zip(decoded, small) { maxErr = max(maxErr, abs(d.0 - o.0), abs(d.1 - o.1)) }
        #expect(maxErr < 1e-5)
        #expect(RunGeo.encode([(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")   // Google's example
    }

    @Test func recordAndPersonalBests() {
        let track = steady(meters: 5100, speed: 3.5)
        let run = RunRecord.from(track, endedAt: track.points.last!.time, weightKg: 70)
        #expect(run.efforts["5k"] != nil && run.efforts["10k"] == nil)
        #expect(run.splitsKm.count == 5)
        #expect(abs(Double(run.calories) - 5.1 * 70 * 1.036) < 6)
        let slower = RunRecord(startedAt: t0, endedAt: t0, movingSeconds: 2000, distanceMeters: 5000, route: "",
                               splitsMile: [], splitsKm: [], efforts: ["5k": 1900], calories: 0)
        let best5k = RunRecords.bests([run, slower]).first { $0.label == "5K" }!
        #expect(best5k.runId == run.id)
        let merged = RunMonth.merge(local: RunMonth(runs: [run]), remote: RunMonth(runs: [slower, run]))
        #expect(merged.runs.count == 2)
    }
}

struct RunFollowersTests {
    @Test func olderSettingsWithoutFollowersStillLoad() throws {
        let s = try JSONDecoder().decode(RunSettings.self, from: Data(#"{"unit":"mi"}"#.utf8))
        #expect(s.followerList.isEmpty && s.followersLine == nil)
    }

    @Test func followersLine() {
        var s = RunSettings(unit: .miles)
        s.followers = [RunFollower(id: "b", name: "Brittany"), RunFollower(id: "s", name: "Sal")]
        #expect(s.followersLine == "Brittany, Sal")
        s.followers?.append(contentsOf: [RunFollower(id: "j", name: "Joe"), RunFollower(id: "r", name: "Renee")])
        #expect(s.followersLine == "Brittany, Sal +2")
    }
}

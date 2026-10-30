import Foundation
import Testing
@testable import FavWidgetsCore

/// FavRun survives the app being closed mid-run (Wes, 2026-10-30).
struct RunCheckpointTests {
    private func dir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("runcp-\(UUID().uuidString)", isDirectory: true)
    }

    private func runningTrack(start: Date) -> RunTrack {
        var t = RunTrack(startedAt: start)
        _ = t.add(RunFix(latitude: 35.2171, longitude: -80.8572, time: start.addingTimeInterval(5), accuracy: 5))
        _ = t.add(RunFix(latitude: 35.2181, longitude: -80.8572, time: start.addingTimeInterval(40), accuracy: 5))
        return t
    }

    @Test func aSavedRunComesBackExactly() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let file = RunCheckpointFile(userId: "wes", directory: dir())
        let cp = RunCheckpoint(userId: "wes", track: runningTrack(start: start), unit: .miles, coachOn: true,
                               coachIntensity: .savage, coachedSplits: 1, clientKey: "k1", liveRunId: "run9",
                               savedAt: start.addingTimeInterval(60))
        try file.save(cp)
        let back = try #require(file.loadResumable(for: "wes", now: start.addingTimeInterval(120)))
        #expect(back == cp)
        #expect(back.track.distance > 100)
        // The clock kept running while the app was gone
        #expect(back.track.movingSeconds(at: start.addingTimeInterval(600)) == 600)
    }

    @Test func aPausedRunStaysPaused() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var track = runningTrack(start: start)
        track.pause(at: start.addingTimeInterval(50))
        let file = RunCheckpointFile(userId: "wes", directory: dir())
        try file.save(RunCheckpoint(userId: "wes", track: track, unit: .kilometers, coachOn: false, coachIntensity: .savage,
                                    coachedSplits: 0, clientKey: "k", liveRunId: nil, savedAt: start.addingTimeInterval(55)))
        let back = try #require(file.loadResumable(for: "wes", now: start.addingTimeInterval(3600)))
        #expect(back.track.isPaused)
        #expect(back.track.movingSeconds(at: start.addingTimeInterval(3600)) == 50)
    }

    @Test func someoneElsesOrAnOldRunIsNotResumedAndIsCleared() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let directory = dir()
        let cp = RunCheckpoint(userId: "wes", track: runningTrack(start: start), unit: .miles, coachOn: false,
                               coachIntensity: .savage, coachedSplits: 0, clientKey: "k", liveRunId: nil, savedAt: start)
        let mine = RunCheckpointFile(userId: "wes", directory: directory)
        try mine.save(cp)
        #expect(mine.loadResumable(for: "sal", now: start) == nil)
        try mine.save(cp)
        #expect(mine.loadResumable(for: "wes", now: start.addingTimeInterval(RunCheckpoint.maxAge + 1)) == nil)
        #expect(!FileManager.default.fileExists(atPath: mine.url.path))
    }

    @Test func eachPersonHasTheirOwnFile() {
        let directory = dir()
        #expect(RunCheckpointFile(userId: "a/b", directory: directory).url != RunCheckpointFile(userId: "ab", directory: directory).url)
    }
}

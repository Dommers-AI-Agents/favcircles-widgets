import Testing
import Foundation
@testable import FavWidgetsCore

struct RunShareTests {
    private func run(_ extra: String = "") -> SharedRun {
        let json = """
        {"id":"r1","ownerId":"wes","ownerName":"Wes","ownerAvatarUrl":null,"isMine":false,"status":"live","unit":"mi",
         "startedAt":"2026-10-06T12:00:00Z","finishedAt":null,"updatedAt":"2026-10-06T12:20:00Z","isPaused":false,
         "distanceM":3218.688,"movingSec":1200,"movingAsOf":"2026-10-06T12:20:00Z","splits":[600,600],"route":"_p~iF~ps|U_ulLnnqC",
         "position":{"lat":35.2,"lng":-80.8},"calories":null,"watchers":[{"id":"sal","name":"Sal"}],"invitedCount":1,
         "cheers":[{"fromId":"sal","fromName":"Sal","emoji":"🔥","at":"2026-10-06T12:10:00Z"}],
         "shareUrl":"https://api.favcircles.com/app/run/t","postedAt":null,"watching":true\(extra)}
        """
        return try! JSONDecoder().decode(SharedRun.self, from: Data(json.utf8))
    }

    @Test func decodesAndReadsWell() {
        let r = run()
        #expect(r.isLive && r.runUnit == .miles && r.coordinates.count == 2)
        #expect(RunShare.headline(r) == "Wes is running · 2.00 mi")
    }

    @Test func theWatchersClockKeepsGoingButNotForever() {
        let r = run()
        let asOf = RunShare.parseDate("2026-10-06T12:20:00Z")!
        #expect(RunShare.movingSeconds(r, now: asOf.addingTimeInterval(30)) == 1230)
        #expect(RunShare.movingSeconds(r, now: asOf.addingTimeInterval(3600)) == 1320)   // capped at 2 min of silence
    }

    @Test func onlyNewCheersPopUp() {
        let r = run()
        #expect(RunShare.newCheers(r.cheers, seen: []).count == 1)
        #expect(RunShare.newCheers(r.cheers, seen: [RunShare.key(r.cheers[0])]).isEmpty)
    }
}

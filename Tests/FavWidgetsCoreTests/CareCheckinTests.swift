import Testing
import Foundation
@testable import FavWidgetsCore

// MARK: - Siblings

@Suite("Care watchers")
struct CareWatcherTests {
    /// A server that predates watchers must still decode — a widget that
    /// refuses to parse is a blank screen, and this one is how a family finds
    /// out a parent has gone quiet.
    @Test func aPlanWithoutWatchersStillDecodes() throws {
        let json = """
        {"planId":"p1","role":"owner","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom",
         "status":"active","questions":[],"usesDefaultQuestions":true,"defaultQuestions":[],
         "times":["08:30"],"timezone":"America/New_York"}
        """
        let plan = try JSONDecoder().decode(CarePlan.self, from: Data(json.utf8))
        #expect(plan.watchers.isEmpty)
        #expect(plan.activeWatchers.isEmpty)
        #expect(plan.isOwner)
    }

    @Test func rolesSplitReadersFromTheOneWhoSetItUp() throws {
        let json = """
        {"planId":"p1","role":"watcher","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom",
         "status":"active","watchers":[
           {"userId":"c2","name":"Kate","status":"active"},
           {"userId":"c3","name":"Sam","status":"invited"}]}
        """
        let plan = try JSONDecoder().decode(CarePlan.self, from: Data(json.utf8))
        #expect(plan.isWatcher)
        #expect(!plan.isOwner)
        #expect(plan.activeWatchers.map(\.name) == ["Kate"])
        #expect(plan.pendingWatchers.map(\.name) == ["Sam"])
    }

    @Test func watchedPlansListAlongsideOwnedOnes() throws {
        let json = """
        {"asOwner":[{"planId":"p1","role":"owner","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom","status":"active"}],
         "asParent":[],
         "asWatcher":[{"planId":"p2","role":"watcher","ownerId":"c2","ownerName":"Kate","parentId":"d1","parentName":"Dad","status":"active"}]}
        """
        let plans = try JSONDecoder().decode(CarePlans.self, from: Data(json.utf8))
        #expect(plans.following.map(\.planId) == ["p1", "p2"])
        #expect(!plans.isEmpty)

        // An older server sends neither key.
        let old = try JSONDecoder().decode(CarePlans.self, from: Data(#"{"asOwner":[],"asParent":[]}"#.utf8))
        #expect(old.asWatcher.isEmpty)
        #expect(old.isEmpty)
    }
}

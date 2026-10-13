import Testing
import Foundation
@testable import FavWidgets
@testable import FavWidgetsCore

/// 2026-10-13: the "start live run" reply was lost on a weak signal and
/// Brittany, Amanda and Joseph were never told. Now they stay queued, the
/// screen says so, and a retry (same run, via clientKey) tells them.
@MainActor
struct RunLiveRetryTests {
    private let runJSON = """
    {"success":true,"run":{"id":"run1","ownerId":"wes","ownerName":"Wes","ownerAvatarUrl":null,"isMine":true,"status":"live","unit":"mi","startedAt":"2026-10-13T22:33:33Z","finishedAt":null,"updatedAt":"2026-10-13T22:33:34Z","isPaused":false,"distanceM":0,"movingSec":0,"movingAsOf":"2026-10-13T22:33:34Z","splits":[],"route":"","position":null,"calories":null,"watchers":[],"invitedCount":0,"cheers":[],"shareUrl":"https://api.favcircles.com/app/run/x","postedAt":null,"watching":false}}
    """

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @Test func followersAreToldOnceTheSignalComesBack() async throws {
        let host = MockWidgetHost()
        let model = WidgetsTabModel(host: host, theme: .default)
        let descriptor = try #require(model.descriptors.first { $0.id == "run" })
        let context = model.context(for: descriptor)
        let session = RunSession.shared
        defer { session.discard() }
        let followers = [RunFollower(id: "brit", name: "Brittany"), RunFollower(id: "amanda", name: "Amanda"), RunFollower(id: "joseph", name: "Joseph")]

        // No scripted reply: the start fails like a lost reply
        session.start(context: context, unit: .miles, followers: followers)
        await waitUntil { session.liveNoSignal }
        #expect(session.followersWaiting.count == 3)
        #expect(session.followersStatus == "📵 No signal · we'll tell Brittany, Amanda and Joseph when you're back")
        #expect(session.liveRun == nil)

        // Signal's back: the retry gets the run and sends the invites
        host.apiResponses["POST widgets/run/live"] = Data(runJSON.utf8)
        host.apiResponses["POST widgets/run/run1/invite"] = Data(#"{"success":true,"invited":3}"#.utf8)
        host.apiResponses["POST widgets/run/run1/progress"] = Data(#"{"ok":true,"cheers":[],"watchers":[]}"#.utf8)
        await waitUntil { true }
        session.attemptLive()
        await waitUntil { session.followersWaiting.isEmpty }
        #expect(session.liveRun?.id == "run1")
        #expect(session.followersTold.map(\.name) == ["Brittany", "Amanda", "Joseph"])
        #expect(session.followersStatus == "👀 Brittany, Amanda and Joseph know you're running")
        #expect(!session.liveNoSignal)

        // Both tries carried the same clientKey, so the server returns one run
        let keys = host.apiRequests.filter { $0.path == "widgets/run/live" }.compactMap { req -> String? in
            guard let body = req.body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            return json["clientKey"] as? String
        }
        #expect(keys.count == 2 && Set(keys).count == 1)
        let invite = try #require(host.apiRequests.first { $0.path == "widgets/run/run1/invite" })
        let ids = (try JSONSerialization.jsonObject(with: try #require(invite.body)) as? [String: Any])?["userIds"] as? [String]
        #expect(ids == ["brit", "amanda", "joseph"])
    }
}

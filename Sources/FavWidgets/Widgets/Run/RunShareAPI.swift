import Foundation
import FavWidgetsCore

/// `/api/widgets/run/...`: watch a run live, cheers, post to activity.
struct RunShareClient {
    let context: WidgetContext

    private struct RunResponse: Decodable { let run: SharedRun }
    private struct RunsResponse: Decodable { let runs: [SharedRun] }
    private struct InviteResponse: Decodable { let invited: Int }
    private struct ProgressResponse: Decodable { let cheers: [SharedRun.Cheer]?; let watchers: [String]? }
    private struct PostResponse: Decodable { let runId: String }
    private struct OK: Decodable { let success: Bool }

    func startLive(unit: RunUnit, startedAt: Date) async throws -> SharedRun {
        let r: RunResponse = try await context.api(.post, "widgets/run/live", body: [
            "unit": unit.label, "startedAt": ISO8601DateFormatter().string(from: startedAt)
        ])
        return r.run
    }
    func invite(_ id: String, userIds: [String]) async throws -> Int {
        let r: InviteResponse = try await context.api(.post, "widgets/run/\(id)/invite", body: ["userIds": userIds]); return r.invited
    }
    func watch(_ id: String) async throws -> SharedRun {
        let r: RunResponse = try await context.api(.post, "widgets/run/\(id)/watch"); return r.run
    }
    func join(token: String) async throws -> SharedRun {
        let r: RunResponse = try await context.api(.post, "widgets/run/join", body: ["token": token]); return r.run
    }
    func get(_ id: String) async throws -> SharedRun {
        let r: RunResponse = try await context.api(.get, "widgets/run/\(id)"); return r.run
    }
    func watching() async throws -> [SharedRun] {
        let r: RunsResponse = try await context.api(.get, "widgets/run/watching"); return r.runs
    }
    func progress(_ id: String, body: [String: Any]) async throws -> (cheers: [SharedRun.Cheer], watchers: [String]) {
        let r: ProgressResponse = try await context.api(.post, "widgets/run/\(id)/progress", body: body); return (r.cheers ?? [], r.watchers ?? [])
    }
    func finish(_ id: String, body: [String: Any]) async throws { let _: OK = try await context.api(.post, "widgets/run/\(id)/finish", body: body) }
    func cancel(_ id: String) async throws { let _: OK = try await context.api(.delete, "widgets/run/\(id)") }
    func cheer(_ id: String, emoji: String) async throws { let _: OK = try await context.api(.post, "widgets/run/\(id)/cheer", body: ["emoji": emoji]) }
    func post(runId: String?, record: RunRecord, unit: RunUnit, audience: String, listId: String?, mapImageUrl: URL?) async throws -> String {
        var body: [String: Any] = ["audience": audience, "summary": RunShareClient.summary(record, unit: unit)]
        if let runId { body["runId"] = runId }
        if let listId { body["audienceListId"] = listId }
        if let mapImageUrl { body["mapImageUrl"] = mapImageUrl.absoluteString }
        let r: PostResponse = try await context.api(.post, "widgets/run/post", body: body); return r.runId
    }

    static func summary(_ record: RunRecord, unit: RunUnit) -> [String: Any] {
        [
            "unit": unit.label, "startedAt": ISO8601DateFormatter().string(from: record.startedAt),
            "distanceM": record.distanceMeters, "movingSec": record.movingSeconds, "route": record.route,
            "splits": record.splits(unit), "calories": record.calories
        ]
    }
}

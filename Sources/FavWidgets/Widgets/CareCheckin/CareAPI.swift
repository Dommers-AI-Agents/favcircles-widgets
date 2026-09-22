import Foundation
import FavWidgetsCore

/// The check-in endpoints. Server-owned; every write returns the plan.
enum CareAPI {
    private struct PlanResponse: Decodable { let plan: CarePlan }
    private struct AsksResponse: Decodable { let asks: [CareAsk] }
    private struct AskResponse: Decodable { let ask: CareAsk }

    static func plans(context: WidgetContext) async throws -> CarePlans {
        try WidgetJSON.decode(CarePlans.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/care/plans")))
    }

    static func createPlan(context: WidgetContext, parentId: String, times: [String], questions: [String]) async throws -> CarePlan {
        try await plan(context, .post, "widgets/care/plans", body: ["parentId": parentId, "times": times, "questions": questions])
    }

    static func updatePlan(context: WidgetContext, planId: String, times: [String]? = nil, questions: [String]? = nil, status: String? = nil) async throws -> CarePlan {
        var body: [String: Any] = [:]
        if let times { body["times"] = times }
        if let questions { body["questions"] = questions }
        if let status { body["status"] = status }
        return try await plan(context, .put, "widgets/care/plans/\(planId)", body: body)
    }

    static func endPlan(context: WidgetContext, planId: String) async throws {
        _ = try await context.host.request(WidgetAPIRequest(.delete, "widgets/care/plans/\(planId)"))
    }

    /// The invitation push again. `delivered` is the server's word on whether
    /// the parent's phone got it; the plan itself is unchanged.
    static func resendInvite(context: WidgetContext, planId: String) async throws -> (plan: CarePlan, delivered: Bool) {
        struct Response: Decodable { let plan: CarePlan; let delivered: Bool }
        let response: Response = try await context.api(.post, "widgets/care/plans/\(planId)/invite")
        return (response.plan, response.delivered)
    }

    static func respond(context: WidgetContext, planId: String, accept: Bool) async throws -> CarePlan {
        try await plan(context, .post, "widgets/care/plans/\(planId)/respond", body: ["accept": accept, "timezone": TimeZone.current.identifier])
    }

    // MARK: - Siblings
    //
    // A sibling asks to join, or the owner invites one; either way the PARENT
    // answers. `watcherId` omitted means "me".

    static func requestToJoin(context: WidgetContext, planId: String, watcherId: String? = nil) async throws -> CarePlan {
        var body: [String: Any] = [:]
        if let watcherId { body["watcherId"] = watcherId }
        return try await plan(context, .post, "widgets/care/plans/\(planId)/watchers", body: body)
    }

    /// Join whatever plan already exists on this parent — a sibling knows who
    /// they meant to watch, not the id of the arrangement someone else made.
    static func requestToJoinForParent(context: WidgetContext, parentId: String) async throws -> CarePlan {
        try await plan(context, .post, "widgets/care/join", body: ["parentId": parentId])
    }

    static func respondToWatcher(context: WidgetContext, planId: String, watcherId: String, accept: Bool) async throws -> CarePlan {
        try await plan(context, .post, "widgets/care/plans/\(planId)/watchers/\(watcherId)/respond", body: ["accept": accept])
    }

    static func removeWatcher(context: WidgetContext, planId: String, watcherId: String) async throws -> CarePlan {
        try await plan(context, .delete, "widgets/care/plans/\(planId)/watchers/\(watcherId)")
    }

    static func asks(context: WidgetContext, planId: String) async throws -> [CareAsk] {
        try WidgetJSON.decode(AsksResponse.self, from: await context.host.request(WidgetAPIRequest(.get, "widgets/care/asks?planId=\(planId)&limit=60"))).asks
    }

    static func answer(context: WidgetContext, askId: String, answer: CareAnswer, note: String) async throws -> CareAsk {
        let data = try await context.host.request(WidgetAPIRequest(
            .post, "widgets/care/asks/\(askId)/answer",
            body: try JSONSerialization.data(withJSONObject: ["answer": answer.rawValue, "note": note])))
        return try WidgetJSON.decode(AskResponse.self, from: data).ask
    }

    private static func plan(_ context: WidgetContext, _ method: WidgetAPIRequest.Method, _ path: String, body: [String: Any]? = nil) async throws -> CarePlan {
        let response: PlanResponse = try await context.api(method, path, body: body)
        return response.plan
    }
}

/// Shared by the card and the full view (`context.transient`), so the card
/// shows the last fetched state with no network and the full view opens
/// on it.
@MainActor
final class CareStore: RemoteStore {
    @Published var plans: CarePlans?

    static func shared(_ context: WidgetContext) -> CareStore {
        context.transient("care.store") { CareStore() }
    }

    func loadIfNeeded(context: WidgetContext) async {
        await loadIfNeeded { self.plans = try await CareAPI.plans(context: context) }
    }

    func load(context: WidgetContext) async {
        await load { self.plans = try await CareAPI.plans(context: context) }
    }

    /// Slots an updated plan into whichever list it belongs to.
    func apply(_ plan: CarePlan) {
        var current = plans ?? CarePlans()
        if plan.isOwner {
            if let i = current.asOwner.firstIndex(where: { $0.planId == plan.planId }) { current.asOwner[i] = plan } else { current.asOwner.insert(plan, at: 0) }
        } else {
            if let i = current.asParent.firstIndex(where: { $0.planId == plan.planId }) { current.asParent[i] = plan } else { current.asParent.insert(plan, at: 0) }
        }
        plans = current
        markLoaded()
    }

    func remove(planId: String) {
        plans?.asOwner.removeAll { $0.planId == planId }
        plans?.asParent.removeAll { $0.planId == planId }
        histories.removeValue(forKey: planId)
    }

    /// Answer history per plan, fetched once per store rather than on every
    /// open of the detail sheet. `apply` on an answer invalidates it.
    @Published private(set) var histories: [String: [CareAsk]] = [:]

    func history(context: WidgetContext, planId: String, refresh: Bool = false) async -> [CareAsk] {
        if !refresh, let cached = histories[planId] { return cached }
        let asks = (try? await CareAPI.asks(context: context, planId: planId)) ?? histories[planId] ?? []
        histories[planId] = asks
        return asks
    }
}

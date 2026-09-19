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

    static func respond(context: WidgetContext, planId: String, accept: Bool) async throws -> CarePlan {
        try await plan(context, .post, "widgets/care/plans/\(planId)/respond", body: ["accept": accept, "timezone": TimeZone.current.identifier])
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
        let data = try await context.host.request(WidgetAPIRequest(method, path, body: body.map { try? JSONSerialization.data(withJSONObject: $0) } ?? nil))
        return try WidgetJSON.decode(PlanResponse.self, from: data).plan
    }
}

/// Shared by the card and the full view (`context.transient`), so the card
/// shows the last fetched state with no network and the full view opens
/// on it.
@MainActor
final class CareStore: ObservableObject {
    @Published var plans: CarePlans?
    @Published var isLoading = false
    @Published var loadError: String?
    private var hasLoaded = false

    static func shared(_ context: WidgetContext) -> CareStore {
        context.transient("care.store") { CareStore() }
    }

    func loadIfNeeded(context: WidgetContext) async {
        guard !hasLoaded, !isLoading else { return }
        await load(context: context)
    }

    func load(context: WidgetContext) async {
        isLoading = true
        defer { isLoading = false }
        do {
            plans = try await CareAPI.plans(context: context)
            hasLoaded = true
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
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
        hasLoaded = true
    }

    func remove(planId: String) {
        plans?.asOwner.removeAll { $0.planId == planId }
        plans?.asParent.removeAll { $0.planId == planId }
    }
}

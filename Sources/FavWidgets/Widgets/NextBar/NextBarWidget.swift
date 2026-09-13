import SwiftUI
import FavWidgetsCore

/// "Where next?" — suggests a bar from the user's own saved bars and the
/// bars their connections and followed people saved: random, weighted
/// toward whatever is closest right now.
public struct NextBarWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "nextbar",
        title: "NextBar",
        subtitle: "Your next bar, picked from your circles",
        symbolName: "wineglass.fill",
        accentHex: "#9F7AEA",
        category: .social,
        storage: .single
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(NextBarCardView(context: context, state: context.state(NextBarSettings.self), pool: NextBarPool.shared(in: context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(NextBarFullView(context: context, state: context.state(NextBarSettings.self), pool: NextBarPool.shared(in: context)))
    }
}

enum NextBarFormat {
    static func distance(_ meters: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

    static func attribution(_ source: WidgetPlaceSource, savedBy: String?) -> String {
        switch source {
        case .mine: return "on your list"
        case .connection: return savedBy.map { "saved by \($0)" } ?? "saved by a connection"
        case .following: return savedBy.map { "via \($0)" } ?? "from someone you follow"
        }
    }
}

/// The fetched candidate pool plus the user's location; lives in memory
/// for the session so card and full view share one fetch.
@MainActor
final class NextBarPool: ObservableObject {
    enum Status: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var candidates: [WidgetPlaceCandidate] = []
    @Published private(set) var origin: WidgetCoordinate?
    @Published private(set) var status: Status = .idle
    @Published private(set) var locationDenied = false

    private let context: WidgetContext
    private var loadTask: Task<Void, Never>?

    init(context: WidgetContext) {
        self.context = context
    }

    static func shared(in context: WidgetContext) -> NextBarPool {
        context.transient("nextbar.pool") { NextBarPool(context: context) }
    }

    func loadIfNeeded() async {
        guard status == .idle else { return }
        await reload()
    }

    func reload() async {
        if let loadTask { await loadTask.value; return }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        status = .loading
        let location = await context.host.currentLocation()
        origin = location
        locationDenied = location == nil
        do {
            let query = WidgetPlaceQuery(categories: ["bar"], near: location, radiusMeters: 50_000)
            candidates = try await context.host.fetchPlaces(query)
            status = .loaded
        } catch {
            status = .failed("Couldn't load bars — pull to refresh")
        }
    }

    func scored(for settings: NextBarSettings) -> [NextBarPicker.Scored] {
        NextBarPicker.pool(candidates, origin: origin, maxDistanceMeters: settings.maxDistanceMeters, sources: settings.sources)
    }

    /// Rolls (or re-rolls) tonight's pick into the persisted settings.
    func roll(into state: WidgetStateController<NextBarSettings>, today: DayKey) -> NextBarPicker.Scored? {
        let pool = scored(for: state.model)
        guard let chosen = NextBarPicker.pick(from: pool, excluding: state.model.recentPickIds) else { return nil }
        let pick = NextBarPick(day: today, placeId: chosen.candidate.id, name: chosen.candidate.name,
                               source: chosen.candidate.source, savedByName: chosen.candidate.savedByName,
                               distanceMeters: chosen.distanceMeters)
        state.update { $0.notePick(pick) }
        return chosen
    }

    func candidate(id: String) -> WidgetPlaceCandidate? {
        candidates.first { $0.id == id }
    }
}

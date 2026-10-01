import SwiftUI
import FavWidgetsCore

/// "What to Eat": for the indecisive. Spins a cuisine and a dish, then
/// finds restaurants you or your people saved that serve it.
public struct WhatToEatWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "whattoeat",
        title: "What to Eat",
        subtitle: "Can't decide? Spin for dinner",
        symbolName: "fork.knife.circle.fill",
        accentHex: "#DD6B20",
        category: .social,
        storage: .single,
        shareBlurb: "Can't decide what to eat? One tap picks for you."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WhatToEatCardView(context: context, state: context.state(WhatToEatSettings.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(WhatToEatFullView(context: context, state: context.state(WhatToEatSettings.self),
                                  pool: WhatToEatPool.shared(in: context)))
    }
}

extension WidgetStateController where Model == WhatToEatSettings {
    @discardableResult
    func spin() -> CravingPicker.Spin? {
        guard let spin = CravingPicker.spin(filters: model.filters, cuisineId: model.cuisineFilter, excluding: model.recentKeys) else { return nil }
        update { $0.noteSpin(spin) }
        return spin
    }
}

/// Saved restaurants near the user; fetched once per session.
@MainActor
final class WhatToEatPool: ObservableObject {
    enum Status: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var candidates: [WidgetPlaceCandidate] = []
    @Published private(set) var origin: WidgetCoordinate?
    @Published private(set) var status: Status = .idle
    @Published private(set) var locationDenied = false

    private let context: WidgetContext

    init(context: WidgetContext) { self.context = context }

    static func shared(in context: WidgetContext) -> WhatToEatPool {
        context.transient("whattoeat.pool") { WhatToEatPool(context: context) }
    }

    func loadIfNeeded() async {
        guard status == .idle else { return }
        await reload()
    }

    func reload() async {
        status = .loading
        let location = await context.host.currentLocation()
        origin = location
        locationDenied = location == nil
        do {
            candidates = try await context.host.fetchPlaces(WidgetPlaceQuery(categories: ["restaurant"], near: location, radiusMeters: 50_000))
            status = .loaded
        } catch {
            status = .failed("Couldn't load restaurants. Pull to refresh.")
        }
    }

    func matches(for settings: WhatToEatSettings) -> [CravingPicker.PlaceMatch] {
        CravingPicker.places(for: settings.currentCuisine, candidates: candidates, origin: origin,
                             maxDistanceMeters: settings.maxDistanceMeters, sources: settings.sources)
    }
}

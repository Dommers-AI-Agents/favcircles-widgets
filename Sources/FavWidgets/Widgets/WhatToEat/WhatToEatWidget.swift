import SwiftUI
import FavWidgetsCore
#if canImport(MapKit)
import MapKit
#endif

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

    /// Map-search results per cuisine id, for this session.
    @Published private(set) var spots: [String: [NearbySpot]] = [:]
    @Published private(set) var searching: Set<String> = []

    /// Asks Apple Maps for this cuisine near the user (once per cuisine per
    /// session). No location, no search: nothing is made up.
    func searchNearby(_ cuisine: Cuisine) async {
        guard spots[cuisine.id] == nil, !searching.contains(cuisine.id), let origin else { return }
        searching.insert(cuisine.id)
        defer { searching.remove(cuisine.id) }
        #if canImport(MapKit)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cuisine.searchQuery
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                                            latitudinalMeters: 16_000, longitudinalMeters: 16_000)
        do {
            let response = try await MKLocalSearch(request: request).start()
            spots[cuisine.id] = response.mapItems.prefix(25).compactMap { item in
                guard let name = item.name else { return nil }
                let c = item.placemark.coordinate
                let pm = item.placemark
                let street = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
                let address = [street.isEmpty ? nil : street, pm.locality].compactMap { $0 }.joined(separator: ", ")
                return NearbySpot(name: name, address: address.isEmpty ? nil : address,
                                  coordinate: WidgetCoordinate(latitude: c.latitude, longitude: c.longitude),
                                  phone: item.phoneNumber, url: item.url)
            }
        } catch {
            spots[cuisine.id] = []
        }
        #else
        spots[cuisine.id] = []
        #endif
    }

    func whereToGet(for settings: WhatToEatSettings) -> CravingPicker.Where {
        let cuisine = settings.currentCuisine
        return CravingPicker.whereToGet(cuisine, candidates: candidates, spots: cuisine.flatMap { spots[$0.id] } ?? [],
                                        origin: origin, maxDistanceMeters: settings.maxDistanceMeters, sources: settings.sources)
    }

    func matches(for settings: WhatToEatSettings) -> [CravingPicker.PlaceMatch] {
        CravingPicker.places(for: settings.currentCuisine, candidates: candidates, origin: origin,
                             maxDistanceMeters: settings.maxDistanceMeters, sources: settings.sources)
    }
}

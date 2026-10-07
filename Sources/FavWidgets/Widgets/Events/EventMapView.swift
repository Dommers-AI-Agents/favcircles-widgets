import SwiftUI
import MapKit
import FavWidgetsCore

/// Every place the group tagged, on a map (Wes, 2026-10-07): tap a pin for
/// who tagged it, Add to my circle, Directions. The same places live in the
/// event circle on your profile once you add them — the map points there too.
struct EventMapSheet: View {
    let context: WidgetContext
    @ObservedObject var model: EventDetailModel
    let event: EventSummary
    /// Close the event and open the circle on the profile
    let onOpenCircle: (String) -> Void
    @State private var selectedId: String?
    @State private var saving: String?
    @State private var tagging = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        let places = model.places
        NavigationStack {
            VStack(spacing: 0) {
                if places.isEmpty {
                    VStack(spacing: 12) {
                        Text("🗺️").font(.system(size: 54))
                        Text("No places yet").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                        Text("Tag the spots you hit and they show up here for everyone in \(event.name).")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
                        tagButton
                    }
                    .padding(32).frame(maxHeight: .infinity)
                } else {
                    EventPlacesMap(places: places, selectedId: $selectedId, accent: context.accent)
                        .frame(maxHeight: .infinity)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let selected = places.first(where: { $0.id == selectedId }) {
                                card(selected, theme: theme)
                            }
                            ForEach(places.filter { $0.id != selectedId }) { place in
                                Button { withAnimation { selectedId = place.id } } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(context.accent)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                                            Text("Tagged by \(place.taggedByName)").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                                        }
                                        Spacer()
                                        if place.savedByMe { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                    }
                                    .padding(.vertical, 4).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            if let circleId = event.myCircleId {
                                Button { onOpenCircle(circleId) } label: {
                                    Label("Open my \(event.name) circle", systemImage: "circle.grid.2x2.fill")
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                                        .frame(maxWidth: .infinity).frame(height: 44)
                                        .background(Capsule().fill(context.accent.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                Text("The places you add are kept in that circle on your profile too.")
                                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                            }
                            if !event.hasEnded { tagButton }
                        }
                        .padding(16)
                    }
                    .frame(maxHeight: 320)
                    .background(theme.background)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("\(event.emoji) \(event.name) map")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { if selectedId == nil { selectedId = places.first?.id } }
        .sheet(isPresented: $tagging) {
            EventTagPlaceSheet(context: context) { candidate in
                Task { @MainActor in
                    if let place = try? await EventsClient(context: context).tag(model.eventId, place: candidate) {
                        model.upsertPlace(place)
                        selectedId = place.id
                        context.host.haptic(.success)
                        context.track("event_place_tagged", ["from": "map"])
                    }
                }
            }
        }
    }

    private var tagButton: some View {
        Button { tagging = true } label: {
            Label("Tag a place", systemImage: "mappin.and.ellipse")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(context.accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func card(_ place: EventPlace, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name).font(.system(size: 19, weight: .bold)).foregroundStyle(theme.label)
            if !place.address.isEmpty { Text(place.address).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
            Text("Tagged by \(place.taggedByName)\(place.savedCount > 0 ? " · saved by \(place.savedCount)" : "")")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            HStack(spacing: 10) {
                if place.savedByMe {
                    Label("In your circle", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.green)
                        .frame(maxWidth: .infinity).frame(height: 40)
                } else {
                    Button { save(place) } label: {
                        Text(saving == place.id ? "Adding…" : "Add to my circle").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().fill(context.accent))
                    }
                    .buttonStyle(.plain).disabled(saving != nil)
                }
                Button { directions(place) } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().fill(context.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
    }

    private func save(_ place: EventPlace) {
        saving = place.id
        Task { @MainActor in
            defer { saving = nil }
            do {
                let result = try await EventsClient(context: context).save(model.eventId, place: place.id)
                model.upsertPlace(result.place)
                await model.load()   // myCircleId appears with the first save
                context.host.haptic(.success)
                context.track("event_place_saved", ["from": "map"])
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save", message: "Check your connection and try again."))
            }
        }
    }

    private func directions(_ place: EventPlace) {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: "\(place.lat),\(place.lng)"), URLQueryItem(name: "q", value: place.name)]
        if let url = c.url { context.host.openURL(url) }
        context.track("event_place_directions")
    }
}

/// The tagged places as pins; the selected one is bigger.
struct EventPlacesMap: View {
    let places: [EventPlace]
    @Binding var selectedId: String?
    let accent: Color
    var interactive = true
    @State private var region = MKCoordinateRegion()

    var body: some View {
        Map(coordinateRegion: $region, interactionModes: interactive ? .all : [], annotationItems: places) { place in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)) {
                let selected = place.id == selectedId
                Button { withAnimation { selectedId = place.id } } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: selected ? 38 : 28))
                            .foregroundStyle(.white, selected ? accent : accent.opacity(0.8))
                            .shadow(radius: 3)
                        if selected {
                            Text(place.name).font(.system(size: 11, weight: .bold)).foregroundStyle(.primary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.background))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
            }
        }
        .onAppear { region = EventPlacesMap.fit(places) }
        .onChange(of: places.count) { _ in region = EventPlacesMap.fit(places) }
    }

    static func fit(_ places: [EventPlace]) -> MKCoordinateRegion {
        EventRecapMap.region(coordinates: places.map { ($0.lat, $0.lng) })
    }
}

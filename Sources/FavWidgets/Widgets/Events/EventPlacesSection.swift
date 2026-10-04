import SwiftUI
import FavWidgetsCore

/// Places the group went: tag one, and add it to your own circle named
/// after the event (public, created the first time).
struct EventPlacesSection: View {
    let context: WidgetContext
    @ObservedObject var model: EventDetailModel
    let event: EventSummary
    @State private var tagging = false
    @State private var saving: String?

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 12) {
            Button { tagging = true } label: {
                Label("Tag a place", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(context.accent, lineWidth: 1.5))
                    .foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
            if model.places.isEmpty {
                Text("Tag the spots you hit tonight. Anyone can add them to their own \(event.name) circle with one tap.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(model.places) { place in
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 26)).foregroundStyle(context.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        if !place.address.isEmpty {
                            Text(place.address).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                        }
                        Text("Tagged by \(place.taggedByName)\(place.savedCount > 0 ? " · saved by \(place.savedCount)" : "")")
                            .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                    if place.savedByMe {
                        Label("Saved", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly)
                            .font(.system(size: 22)).foregroundStyle(.green)
                            .accessibilityLabel("In your \(event.name) circle")
                    } else {
                        Button { save(place) } label: {
                            Text(saving == place.id ? "…" : "Add").font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(context.accent)).foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(saving != nil)
                        .accessibilityLabel("Add \(place.name) to my \(event.name) circle")
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
            }
        }
        .sheet(isPresented: $tagging) {
            EventTagPlaceSheet(context: context) { candidate in
                Task { @MainActor in
                    if let place = try? await EventsClient(context: context).tag(model.eventId, place: candidate) {
                        model.upsertPlace(place)
                        context.host.haptic(.success)
                        context.track("event_place_tagged")
                    }
                }
            }
        }
    }

    private func save(_ place: EventPlace) {
        saving = place.id
        Task { @MainActor in
            defer { saving = nil }
            do {
                let result = try await EventsClient(context: context).save(model.eventId, place: place.id)
                model.upsertPlace(result.place)
                context.host.haptic(.success)
                context.track("event_place_saved")
                context.host.presentAlert(WidgetAlert(title: "Saved", message: EventCopy.savedToCircle(placeName: place.name, eventName: event.name)))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save", message: "Check your connection and try again."))
            }
        }
    }
}

/// Search any venue near you (Apple Maps), or pick from your saved places.
struct EventTagPlaceSheet: View {
    let context: WidgetContext
    let onPick: (WidgetPlaceCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WidgetPlaceCandidate] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Tag a place", theme: theme) {
            VStack(spacing: 12) {
                WidgetUI.textField("Search bars, restaurants, anywhere", text: $query, theme: theme)
                    .padding(.horizontal, 16)
                List(results) { place in
                    Button { onPick(place); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            if let address = place.address, !address.isEmpty {
                                Text(address).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay { if searching && results.isEmpty { ProgressView() } }
            }
            .padding(.top, 12)
        }
        .onChange(of: query) { _ in scheduleSearch() }
        .task { await search("") }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await search(query)
        }
    }

    /// Empty text = what's around you right now.
    private func search(_ text: String) async {
        searching = true
        defer { searching = false }
        let here = await context.host.currentLocation()
        let found = (try? await context.host.searchPlaces(text.isEmpty ? "bar restaurant" : text, near: here)) ?? []
        if !Task.isCancelled { results = found }
    }
}

import SwiftUI
import MapKit
import FavWidgetsCore

/// "Current location" or a city/address that stays. `onPick(nil)` = current.
struct WeatherPlacePicker: View {
    let theme: WidgetTheme
    let onPick: (WeatherPlace?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false

    var body: some View {
        WidgetSheet(title: "Weather location", theme: theme) {
            List {
                Section {
                    Button { onPick(nil); dismiss() } label: {
                        Label("Current location", systemImage: "location.fill").foregroundStyle(theme.label)
                    }
                }
                Section {
                    TextField("Search a city or address", text: $query)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    if searching { ProgressView() }
                    ForEach(results, id: \.self) { place in
                        Button { onPick(place); dismiss() } label: {
                            Label(place.name, systemImage: "mappin.circle").foregroundStyle(theme.label)
                        }
                    }
                } footer: {
                    Text("A place you pick stays until you change it.")
                }
            }
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 350_000_000)   // wait for typing to pause
                await search()
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = .address
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        var seen = Set<String>()
        results = items.compactMap { item in
            let pm = item.placemark
            let name = [pm.locality ?? pm.name, pm.administrativeArea, pm.locality == nil ? nil : pm.countryCode == "US" ? nil : pm.country]
                .compactMap { $0 }.joined(separator: ", ")
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return WeatherPlace(name: name, latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude)
        }
    }
}

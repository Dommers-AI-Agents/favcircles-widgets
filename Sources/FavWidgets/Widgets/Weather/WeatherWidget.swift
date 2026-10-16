import SwiftUI
import FavWidgetsCore

/// Weather (Wes, 2026-10-07): the temperature also sits on the app's home
/// header (`FavWeather.shared.header`); tapping it opens this widget. Saved
/// cities like Apple's Weather app (2026-10-16); the header shows My Location
/// or the city chosen with "Show on the home screen".
public struct WeatherWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "weather",
        title: "Weather",
        subtitle: "Right now, the next hours and 10 days",
        symbolName: "cloud.sun.fill",
        accentHex: "#2B8CD9",
        category: .health,
        storage: .none,
        shareBlurb: "The weather where you are, hour by hour and 10 days out."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WeatherCardView(context: context))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(WeatherFullView(context: context))
    }

    public func refresh(context: WidgetContext) async {
        await FavWeather.shared.refresh(force: true) { await context.host.currentLocation() }
    }
}

/// "72° Sunny · Charlotte · H 78° L 61°"
struct WeatherCardView: View {
    let context: WidgetContext
    @ObservedObject private var weather = FavWeather.shared

    var body: some View {
        let theme = context.theme
        let unit = weather.prefs.resolvedUnit()
        WidgetCard(context: context) {
            if let f = weather.latest {
                HStack(spacing: 14) {
                    Image(systemName: f.now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 38))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeatherFormat.temp(f.now.tempC, unit)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
                        Text([f.now.condition, f.placeName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                    }
                    Spacer()
                    if let today = f.days.first {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("H \(WeatherFormat.temp(today.highC, unit))")
                            Text("L \(WeatherFormat.temp(today.lowC, unit))")
                        }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.secondaryLabel)
                    }
                }
            } else {
                WidgetUI.summary(weather.locationUnavailable ? "Turn on Location, or pick a place"
                                 : weather.unavailable ? "Weather isn't available right now" : "Getting the weather…", theme: theme)
            }
        }
        .task { await weather.refresh { await context.host.currentLocation() } }
    }
}

/// The widget's page, like Apple's Weather app (Wes, 2026-10-16): My
/// Location and the saved cities as cards (local time, condition, temp,
/// high/low over the sky they're under); search to add one; tap a card for
/// its forecast; swipe to delete, Edit to reorder.
struct WeatherFullView: View {
    let context: WidgetContext
    @ObservedObject private var weather = FavWeather.shared
    @State private var query = ""
    @State private var opened: WeatherTarget?
    @State private var attribution: (markLight: URL, markDark: URL, legal: URL)?
    @State private var editing = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = context.theme
        let unit = weather.prefs.resolvedUnit()
        VStack(spacing: 0) {
            searchField(theme)
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                WeatherSearchResults(query: query, theme: theme) { place in
                    opened = .preview(place)
                }
            } else {
                List {
                    Section {
                        Button { opened = .current } label: {
                            WeatherCityCard(title: weather.here?.placeName ?? "My Location",
                                            subtitle: weather.here?.placeName == nil ? nil : "My Location",
                                            forecast: weather.here, unit: unit,
                                            fallback: weather.locationUnavailable ? "Turn on Location for FavCircles" : "Getting the weather\u{2026}")
                        }
                        .buttonStyle(.plain)
                        .weatherCardRow()
                        .moveDisabled(true)
                        .deleteDisabled(true)

                        ForEach(weather.prefs.savedPlaces) { place in
                            Button { opened = .saved(place) } label: {
                                WeatherCityCard(title: place.name.components(separatedBy: ",").first ?? place.name,
                                                subtitle: place.timeZone.map { WeatherClock.localTime(in: $0) },
                                                forecast: weather.forecasts[place.id], unit: unit,
                                                fallback: "Getting the weather\u{2026}")
                            }
                            .buttonStyle(.plain)
                            .weatherCardRow()
                        }
                        .onDelete { offsets in
                            let gone = offsets.map { weather.prefs.savedPlaces[$0] }
                            gone.forEach(weather.removePlace)
                            context.track("weather_city_removed")
                        }
                        .onMove { weather.movePlaces(from: $0, to: $1) }
                    } footer: {
                        VStack(spacing: 14) {
                            if weather.prefs.savedPlaces.isEmpty {
                                Text("Search above to add cities, like the Weather app.")
                                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                            }
                            Picker("Units", selection: Binding(get: { unit }, set: { u in weather.update { $0.unit = u } })) {
                                Text("\u{00B0}F").tag(WeatherUnit.fahrenheit); Text("\u{00B0}C").tag(WeatherUnit.celsius)
                            }
                            .pickerStyle(.segmented)
                            attributionView(theme)
                        }
                        .padding(.top, 8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .weatherEditing(editing)
                .refreshable { await refreshAll(force: true) }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .task {
            await refreshAll(force: false)
            attribution = await weather.attribution()
        }
        .sheet(item: $opened) { target in
            WeatherPlaceSheet(context: context, target: target)
        }
    }

    private func refreshAll(force: Bool) async {
        async let here: Void = weather.refreshHere(force: force) { await context.host.currentLocation() }
        async let saved: Void = weather.refreshSaved(force: force)
        _ = await (here, saved)
    }

    private func searchField(_ theme: WidgetTheme) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryLabel)
                TextField("Search for a city or airport", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(Capsule().fill(theme.secondaryBackground))
            if query.isEmpty && !weather.prefs.savedPlaces.isEmpty {
                Button(editing ? "Done" : "Edit") { withAnimation { editing.toggle() } }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(context.accent)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// Apple's required "Weather" mark and link to its data sources
    @ViewBuilder
    private func attributionView(_ theme: WidgetTheme) -> some View {
        if let a = attribution {
            VStack(spacing: 6) {
                AsyncImage(url: scheme == .dark ? a.markDark : a.markLight) { image in
                    image.resizable().scaledToFit()
                } placeholder: { Color.clear }
                .frame(height: 14)
                Link("Other data sources", destination: a.legal).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Which forecast a sheet shows
enum WeatherTarget: Identifiable, Hashable {
    case current
    case saved(WeatherPlace)
    /// From search, with an Add button
    case preview(WeatherPlace)

    var id: String {
        switch self {
        case .current: return "current"
        case .saved(let p): return "saved-\(p.id)"
        case .preview(let p): return "preview-\(p.id)"
        }
    }

    var place: WeatherPlace? {
        switch self {
        case .current: return nil
        case .saved(let p), .preview(let p): return p
        }
    }
}

private extension View {
    func weatherCardRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    func weatherEditing(_ editing: Bool) -> some View {
        #if os(iOS)
        environment(\.editMode, .constant(editing ? .active : .inactive))
        #else
        self
        #endif
    }
}

/// One city: name, local time (or "My Location"), condition; the temperature
/// and today's high/low on the right; the sky behind.
struct WeatherCityCard: View {
    let title: String
    let subtitle: String?
    let forecast: WeatherForecast?
    let unit: WeatherUnit
    let fallback: String

    var body: some View {
        let sky = WeatherSky.from(symbol: forecast?.now.symbol ?? "cloud")
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                if let subtitle { Text(subtitle).font(.system(size: 14, weight: .semibold)).opacity(0.85) }
                Spacer(minLength: 14)
                Text(forecast?.now.condition ?? fallback).font(.system(size: 15, weight: .medium)).opacity(0.9).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let f = forecast {
                    Text(WeatherFormat.temp(f.now.tempC, unit)).font(.system(size: 52, weight: .light))
                    Spacer(minLength: 0)
                    if let today = f.days.first {
                        Text("H:\(WeatherFormat.temp(today.highC, unit))  L:\(WeatherFormat.temp(today.lowC, unit))")
                            .font(.system(size: 15, weight: .semibold))
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(WeatherSkyBackground(sky: sky))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A gradient for the sky a city is under right now.
struct WeatherSkyBackground: View {
    let sky: WeatherSky
    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    private var colors: [Color] {
        switch sky {
        case .clearDay: return [Color(red: 0.25, green: 0.55, blue: 0.92), Color(red: 0.42, green: 0.70, blue: 0.96)]
        case .clearNight: return [Color(red: 0.08, green: 0.10, blue: 0.24), Color(red: 0.18, green: 0.20, blue: 0.38)]
        case .cloudy: return [Color(red: 0.42, green: 0.52, blue: 0.64), Color(red: 0.58, green: 0.66, blue: 0.75)]
        case .cloudyNight: return [Color(red: 0.16, green: 0.18, blue: 0.28), Color(red: 0.30, green: 0.32, blue: 0.42)]
        case .rain: return [Color(red: 0.28, green: 0.33, blue: 0.40), Color(red: 0.40, green: 0.45, blue: 0.52)]
        case .snow: return [Color(red: 0.50, green: 0.58, blue: 0.68), Color(red: 0.70, green: 0.76, blue: 0.84)]
        case .storm: return [Color(red: 0.18, green: 0.19, blue: 0.26), Color(red: 0.32, green: 0.31, blue: 0.40)]
        case .fog: return [Color(red: 0.48, green: 0.50, blue: 0.54), Color(red: 0.62, green: 0.64, blue: 0.67)]
        }
    }
}

/// Cities and airports for the search field (Apple Maps).
struct WeatherSearchResults: View {
    let query: String
    let theme: WidgetTheme
    let onPick: (WeatherPlace) -> Void
    @State private var results: [WeatherPlace] = []
    @State private var searching = false

    var body: some View {
        List {
            if searching && results.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            ForEach(results) { place in
                Button { onPick(place) } label: {
                    Text(place.name).font(.system(size: 17)).foregroundStyle(theme.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(Color.clear)
            }
            if !searching && results.isEmpty {
                Text("No results").foregroundStyle(theme.secondaryLabel).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)   // wait for typing to pause
            guard !Task.isCancelled else { return }
            searching = true
            results = await WeatherPlaceSearch.search(query)
            searching = false
        }
    }
}

/// One place's forecast in a sheet. From search it has Add; a saved city or
/// My Location can be put on the home header.
struct WeatherPlaceSheet: View {
    let context: WidgetContext
    let target: WeatherTarget
    @ObservedObject private var weather = FavWeather.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        let unit = weather.prefs.resolvedUnit()
        let forecast: WeatherForecast? = target.place.map { weather.forecasts[$0.id] } ?? weather.here
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let f = forecast {
                        WeatherForecastSections(forecast: f, unit: unit, theme: theme, title: target.place?.name ?? f.placeName ?? "My Location")
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                    headerToggle(theme)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isPreview ? "Cancel" : "Done") { dismiss() }
                }
                if case .preview(let place) = target, !weather.prefs.isSaved(place) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            weather.addPlace(place)
                            context.host.haptic(.success)
                            context.track("weather_city_added")
                            dismiss()
                        }
                        .disabled(weather.prefs.savedPlaces.count >= WeatherPrefs.maxSaved)
                    }
                }
            }
        }
        .task {
            if let place = target.place {
                await weather.refresh(place: place)
            } else {
                await weather.refreshHere { await context.host.currentLocation() }
            }
        }
    }

    private var isPreview: Bool { if case .preview = target { return true } else { return false } }

    /// "Show on the home screen": the temperature next to the bell
    @ViewBuilder
    private func headerToggle(_ theme: WidgetTheme) -> some View {
        if !isPreview {
            let place = target.place
            let shown = place.map { weather.prefs.fixedPlace?.sameSpot(as: $0) == true } ?? (weather.prefs.fixedPlace == nil)
            Button {
                Task { await weather.showOnHeader(place) { await context.host.currentLocation() } }
                context.track("weather_header_place", ["mode": place == nil ? "current" : "fixed"])
            } label: {
                HStack {
                    Image(systemName: shown ? "checkmark.circle.fill" : "circle").foregroundStyle(context.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show on the home screen").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                        Text("The temperature at the top of Home").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
            }
            .buttonStyle(.plain)
            .disabled(shown)
        }
    }
}

/// The forecast for one place: now, the next 24 hours, 10 days, details.
struct WeatherForecastSections: View {
    let forecast: WeatherForecast
    let unit: WeatherUnit
    let theme: WidgetTheme
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            now(forecast)
            hourly(forecast)
            daily(forecast)
            details(forecast)
        }
    }

    private func now(_ f: WeatherForecast) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(theme.label).multilineTextAlignment(.center)
            Text(WeatherFormat.temp(f.now.tempC, unit)).font(.system(size: 72, weight: .thin, design: .rounded)).foregroundStyle(theme.label)
            Text(f.now.condition).font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
            if let today = f.days.first {
                Text("H \(WeatherFormat.temp(today.highC, unit))  L \(WeatherFormat.temp(today.lowC, unit))  \u{00B7}  Feels like \(WeatherFormat.temp(f.now.feelsLikeC, unit))")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hourly(_ f: WeatherForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Next 24 hours", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(f.hours.enumerated()), id: \.element.id) { i, h in
                        VStack(spacing: 6) {
                            Text(i == 0 ? "Now" : h.date.formatted(.dateTime.hour()))
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.secondaryLabel)
                            Image(systemName: h.symbol).symbolRenderingMode(.multicolor).font(.system(size: 20)).frame(height: 24)
                            Text(WeatherFormat.precip(h.precipChance) ?? " ").font(.system(size: 11, weight: .semibold)).foregroundStyle(.cyan)
                            Text(WeatherFormat.temp(h.tempC, unit)).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                        }
                    }
                }
                .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private func daily(_ f: WeatherForecast) -> some View {
        let low = f.days.map(\.lowC).min() ?? 0, high = f.days.map(\.highC).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("10 days", theme: theme)
            VStack(spacing: 0) {
                ForEach(Array(f.days.enumerated()), id: \.element.id) { i, d in
                    HStack(spacing: 10) {
                        Text(i == 0 ? "Today" : d.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label).frame(width: 54, alignment: .leading)
                        VStack(spacing: 0) {
                            Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                            if let p = WeatherFormat.precip(d.precipChance) { Text(p).font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan) }
                        }
                        .frame(width: 34)
                        Text(WeatherFormat.temp(d.lowC, unit)).foregroundStyle(theme.secondaryLabel).frame(width: 38, alignment: .trailing)
                        TemperatureBar(low: d.lowC, high: d.highC, rangeLow: low, rangeHigh: high, theme: theme)
                        Text(WeatherFormat.temp(d.highC, unit)).foregroundStyle(theme.label).frame(width: 38, alignment: .leading)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .padding(.vertical, 8)
                    if i < f.days.count - 1 { Divider().overlay(theme.separator.opacity(0.5)) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private func details(_ f: WeatherForecast) -> some View {
        let cells: [(String, String, String)] = [
            ("humidity", "Humidity", "\(Int((f.now.humidity * 100).rounded()))%"),
            ("wind", "Wind", WeatherFormat.wind(f.now.windKph, unit)),
            ("sun.max", "UV index", "\(f.now.uvIndex)"),
            ("thermometer.medium", "Feels like", WeatherFormat.temp(f.now.feelsLikeC, unit))
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(cells, id: \.1) { c in
                VStack(alignment: .leading, spacing: 6) {
                    Label(c.1, systemImage: c.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                    Text(c.2).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(theme.label)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
            }
        }
    }
}

/// Where in the 10-day range a day's low→high sits
struct TemperatureBar: View {
    let low: Double, high: Double, rangeLow: Double, rangeHigh: Double
    let theme: WidgetTheme
    var body: some View {
        GeometryReader { geo in
            let span = max(rangeHigh - rangeLow, 1)
            let x0 = (low - rangeLow) / span * geo.size.width
            let x1 = (high - rangeLow) / span * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(theme.separator.opacity(0.4))
                Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x1 - x0, 6)).offset(x: x0)
            }
        }
        .frame(height: 5)
    }
}

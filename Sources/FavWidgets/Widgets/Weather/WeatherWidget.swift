import SwiftUI
import FavWidgetsCore

/// Weather (Wes, 2026-10-07): the temperature also sits on the app's home
/// header (`FavWeather.shared.header`); tapping it opens this widget. For
/// your current location or a place you pick that stays.
public struct WeatherWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "weather",
        title: "Weather",
        subtitle: "Right now, the next hours and 10 days",
        symbolName: "cloud.sun.fill",
        accentHex: "#2B8CD9",
        category: .health,
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

struct WeatherFullView: View {
    let context: WidgetContext
    @ObservedObject private var weather = FavWeather.shared
    @State private var picking = false
    @State private var attribution: (markLight: URL, markDark: URL, legal: URL)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = context.theme
        let unit = weather.prefs.resolvedUnit()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                locationRow(theme)
                if let f = weather.latest {
                    now(f, unit, theme)
                    hourly(f, unit, theme)
                    daily(f, unit, theme)
                    details(f, unit, theme)
                } else {
                    Text(weather.locationUnavailable
                         ? "We can't see where you are. Turn on Location for FavCircles, or pick a place."
                         : weather.unavailable ? "Weather isn't available right now. Pull down to try again." : "Getting the weather…")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                Picker("Units", selection: Binding(get: { unit }, set: { u in weather.update { $0.unit = u } })) {
                    Text("°F").tag(WeatherUnit.fahrenheit); Text("°C").tag(WeatherUnit.celsius)
                }
                .pickerStyle(.segmented)
                attributionView(theme)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .refreshable { await weather.refresh(force: true) { await context.host.currentLocation() } }
        .task {
            await weather.refresh { await context.host.currentLocation() }
            attribution = await weather.attribution()
        }
        .sheet(isPresented: $picking) {
            WeatherPlacePicker(theme: theme) { choice in
                weather.update { p in
                    if let choice { p.mode = .fixed; p.place = choice } else { p.mode = .current }
                }
                context.track("weather_location", ["mode": choice == nil ? "current" : "fixed"])
                Task { await weather.refresh(force: true) { await context.host.currentLocation() } }
            }
        }
    }

    private func locationRow(_ theme: WidgetTheme) -> some View {
        Button { picking = true } label: {
            HStack(spacing: 10) {
                Image(systemName: weather.prefs.fixedPlace == nil ? "location.fill" : "mappin.circle.fill")
                    .foregroundStyle(context.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.prefs.fixedPlace?.name ?? weather.latest?.placeName ?? "Current location")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(theme.label)
                    Text(weather.prefs.fixedPlace == nil ? "Current location · Change" : "Always this place · Change")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        }
        .buttonStyle(.plain)
    }

    private func now(_ f: WeatherForecast, _ unit: WeatherUnit, _ theme: WidgetTheme) -> some View {
        VStack(spacing: 4) {
            Image(systemName: f.now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 54))
            Text(WeatherFormat.temp(f.now.tempC, unit)).font(.system(size: 72, weight: .thin, design: .rounded)).foregroundStyle(theme.label)
            Text(f.now.condition).font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
            if let today = f.days.first {
                Text("H \(WeatherFormat.temp(today.highC, unit))  L \(WeatherFormat.temp(today.lowC, unit))  ·  Feels like \(WeatherFormat.temp(f.now.feelsLikeC, unit))")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hourly(_ f: WeatherForecast, _ unit: WeatherUnit, _ theme: WidgetTheme) -> some View {
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

    private func daily(_ f: WeatherForecast, _ unit: WeatherUnit, _ theme: WidgetTheme) -> some View {
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

    private func details(_ f: WeatherForecast, _ unit: WeatherUnit, _ theme: WidgetTheme) -> some View {
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

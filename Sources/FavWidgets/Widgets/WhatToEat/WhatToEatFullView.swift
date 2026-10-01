import SwiftUI
import FavWidgetsCore

struct WhatToEatFullView: View {
    enum Tab: String, CaseIterable { case spin = "Spin a craving", place = "Pick a place" }

    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WhatToEatSettings>
    @ObservedObject var pool: WhatToEatPool
    @State private var tab: Tab = .spin
    @State private var spinning = false
    @State private var reel: (emoji: String, name: String)?
    @State private var pickedPlaceId: String?

    private let distanceChoices: [(label: String, meters: Double)] = [("2 km", 2_000), ("5 km", 5_000), ("15 km", 15_000), ("Any", 100_000)]

    var body: some View {
        let theme = context.theme
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Color.clear.frame(height: 0).id("top")
                Picker("Mode", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if tab == .spin { spinTab } else { placeTab }
            }
            .padding(16)
        }
        .onChange(of: state.model.currentCuisineId) { _ in pickedPlaceId = nil }   // a new craving, a new pick
        .onChange(of: pickedPlaceId) { id in
            if id != nil { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) } }
        }
        }
        .background(theme.background)
        .refreshable { await pool.reload() }
        .task {
            await state.loadIfNeeded()
            if state.model.currentCuisineId == nil { state.spin() }
            await pool.loadIfNeeded()
        }
    }

    // MARK: - Spin a craving

    private var spinTab: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.header("I'm in the mood for…", theme: theme)
                FlowChips(items: CravingTag.allCases) { tag in
                    let on = state.model.filters.contains(tag)
                    Button {
                        context.host.haptic(.selection)
                        state.update { if on { $0.filters.remove(tag) } else { $0.filters.insert(tag) } }
                        runSpin()   // show the effect at once, not on the next Spin
                    } label: {
                        Text("\(tag.emoji) \(tag.label)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? .white : theme.label)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(on ? context.accent : theme.secondaryBackground))
                    }
                    .buttonStyle(.plain)
                }
            }

            cuisineRow

            resultCard

            WidgetUI.primaryButton(spinning ? "Spinning…" : "Spin", color: context.accent) { runSpin() }
                .disabled(spinning)

            if state.model.currentCuisine != nil && !spinning {
                Button {
                    context.track("whattoeat_where_can_i_get_it")
                    withAnimation { tab = .place }
                } label: {
                    Label("Where can I get it?", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Type of food": any cuisine, or one in particular.
    private var cuisineRow: some View {
        let theme = context.theme
        let options: [Cuisine?] = [nil] + CravingLibrary.all
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Type of food", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { cuisine in
                        let on = state.model.cuisineFilter == cuisine?.id
                        Button {
                            context.host.haptic(.selection)
                            state.update { $0.cuisineFilter = cuisine?.id }
                            runSpin()
                        } label: {
                            Text(cuisine.map { "\($0.emoji) \($0.name)" } ?? "🎲 Any")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(on ? .white : theme.label)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(on ? context.accent : theme.secondaryBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// What the result was picked for, e.g. "Healthy · Chinese".
    private var filterCaption: String? {
        var parts = CravingTag.allCases.filter { state.model.filters.contains($0) }.map(\.label)
        if let id = state.model.cuisineFilter, let c = CravingLibrary.cuisine(id: id) { parts.append(c.name) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var resultCard: some View {
        let theme = context.theme
        let cuisine = state.model.currentCuisine
        return VStack(spacing: 8) {
            if spinning, let reel {
                Text(reel.emoji).font(.system(size: 56))
                Text(reel.name).font(.system(size: 22, weight: .bold)).foregroundStyle(theme.secondaryLabel)
            } else if let cuisine, let dish = state.model.currentDish {
                Text(cuisine.emoji).font(.system(size: 56))
                Text(cuisine.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                Text(dish).font(.system(size: 26, weight: .bold)).foregroundStyle(theme.label).multilineTextAlignment(.center)
                if let caption = filterCaption {
                    Text("Picked for: \(caption)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                        .padding(.top, 2)
                }
            } else {
                Text("🎰").font(.system(size: 56))
                Text("Tap Spin").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.secondaryBackground))
        .animation(.spring(response: 0.3), value: state.model.currentDish)
    }

    /// A short slot-machine flicker through cuisines, then the real pick.
    private func runSpin() {
        guard !spinning else { return }
        context.track("whattoeat_spin", ["filters": state.model.filters.map(\.rawValue).sorted().joined(separator: ",")])
        spinning = true
        pickedPlaceId = nil
        Task { @MainActor in
            let delays: [UInt64] = [60, 60, 70, 80, 90, 110, 130, 160, 200, 250]
            for delay in delays {
                if let id = state.model.cuisineFilter, let c = CravingLibrary.cuisine(id: id) {
                    reel = (c.emoji, c.dishes.randomElement()?.name ?? c.name)
                } else {
                    let c = CravingLibrary.all.randomElement()!
                    reel = (c.emoji, c.name)
                }
                context.host.haptic(.selection)
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
            }
            state.spin()
            context.host.haptic(.success)
            spinning = false
            reel = nil
        }
    }

    // MARK: - Pick a place

    /// One thing you could go to: a saved place, or a map result.
    enum Option: Identifiable, Equatable {
        case saved(CravingPicker.PlaceMatch)
        case nearby(NearbySpot)
        var id: String {
            switch self {
            case .saved(let m): return "saved:\(m.scored.candidate.id)"
            case .nearby(let s): return "nearby:\(s.id)"
            }
        }
    }

    private var placeTab: some View {
        let theme = context.theme
        let cuisine = state.model.currentCuisine
        let found = pool.whereToGet(for: state.model)
        let isSearching = cuisine.map { pool.searching.contains($0.id) || (pool.origin != nil && pool.spots[$0.id] == nil) } ?? false
        let all: [Option] = found.saved.map(Option.saved) + found.nearby.map(Option.nearby) + found.otherSaved.map(Option.saved)
        let picked = all.first { $0.id == pickedPlaceId }
        let pickFrom: [Option] = !found.saved.isEmpty ? found.saved.map(Option.saved)
            : !found.nearby.isEmpty ? Array(found.nearby.prefix(6)).map(Option.nearby)
            : found.otherSaved.map(Option.saved)
        return VStack(alignment: .leading, spacing: 16) {
            if let cuisine, let dish = state.model.currentDish {
                Text("\(cuisine.emoji) Craving \(cuisine.name): \(dish)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.label)
            }
            switch pool.status {
            case .loading, .idle:
                HStack(spacing: 8) { ProgressView(); Text("Finding restaurants near you…") }
                    .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            case .failed(let message):
                Text(message).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            case .loaded:
                if pool.locationDenied && found.saved.isEmpty {
                    Text("Turn on location for FavCircles to find \(cuisine?.name ?? "restaurants") near you.")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                }
                if let picked {
                    pickCard(picked, options: pickFrom)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if !pickFrom.isEmpty {
                    WidgetUI.primaryButton(cuisine.map { "Pick \(Self.article(for: $0.name)) \($0.name) spot for me" } ?? "Pick one for me", color: context.accent) {
                        pickForMe(from: pickFrom)
                    }
                }

                // 1. Your saves (and your people's) that serve it
                if let cuisine {
                    WidgetUI.header("\(cuisine.name) from your circles", theme: theme)
                    if found.saved.filter({ Option.saved($0).id != pickedPlaceId }).isEmpty {
                        Text(found.saved.isEmpty
                             ? "None of your saved places serve \(cuisine.name.lowercased()) yet."
                             : "That's the one above.")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                    ForEach(found.saved.filter { Option.saved($0).id != pickedPlaceId }, id: \.scored.candidate.id) { m in
                        placeRow(m)
                        Divider().overlay(theme.separator)
                    }

                    // 2. Real restaurants nearby from Apple Maps
                    WidgetUI.header("More \(cuisine.name.lowercased()) nearby", theme: theme)
                    if isSearching {
                        HStack(spacing: 8) { ProgressView(); Text("Searching the map…") }
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    } else if found.nearby.isEmpty {
                        Text(pool.origin == nil ? "Turn on location to search the map." : "Nothing else within \(NextBarFormat.distance(state.model.maxDistanceMeters)). Try a wider distance below.")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                    ForEach(found.nearby.filter { Option.nearby($0).id != pickedPlaceId }.prefix(12), id: \.id) { spot in
                        nearbyRow(spot)
                        Divider().overlay(theme.separator)
                    }
                }

                // 3. Everything else you've saved, for "just somewhere good"
                if !found.otherSaved.isEmpty {
                    WidgetUI.header(cuisine == nil ? "Your saved spots nearby" : "Or one of your other favorites", theme: theme)
                    ForEach(found.otherSaved.filter { Option.saved($0).id != pickedPlaceId }.prefix(10), id: \.scored.candidate.id) { m in
                        placeRow(m)
                        Divider().overlay(theme.separator)
                    }
                }
            }
            distancePicker
        }
        .task(id: state.model.currentCuisineId) {
            await pool.loadIfNeeded()
            if let cuisine = state.model.currentCuisine { await pool.searchNearby(cuisine) }
        }
    }

    private func distanceText(to coordinate: WidgetCoordinate) -> String? {
        guard let origin = pool.origin else { return nil }
        return "\(NextBarFormat.distance(origin.distance(to: coordinate))) away"
    }

    /// The chosen place, big and on top, with what to do next.
    private func pickCard(_ option: Option, options: [Option]) -> some View {
        let theme = context.theme
        let name: String; let address: String?; let detail: String; let serves: Bool
        switch option {
        case .saved(let m):
            let c = m.scored.candidate
            name = c.name; address = c.address; serves = m.matchesCuisine
            detail = [distanceText(to: c.coordinate), NextBarFormat.attribution(c.source, savedBy: c.savedByName, savers: c.savers)].compactMap { $0 }.joined(separator: " · ")
        case .nearby(let s):
            name = s.name; address = s.address; serves = true
            detail = [distanceText(to: s.coordinate), "found on Apple Maps"].compactMap { $0 }.joined(separator: " · ")
        }
        return VStack(alignment: .leading, spacing: 12) {
            Label("Tonight, go here", systemImage: "star.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(context.accent)
            Text(name).font(.system(size: 26, weight: .bold)).foregroundStyle(theme.label)
            VStack(alignment: .leading, spacing: 4) {
                if let address, !address.isEmpty { Text(address).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel) }
                Text(detail).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                if let dish = state.model.currentDish, serves {
                    Text("Order the \(dish.lowercasedFirst)").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                }
            }
            HStack(spacing: 10) {
                Button { go(option) } label: {
                    Label(Self.isSaved(option) ? "Let's go" : "Directions", systemImage: Self.isSaved(option) ? "figure.walk" : "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent))
                }
                .buttonStyle(.plain)
                Button { pickForMe(from: options) } label: {
                    Label("Pick another", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(options.count < 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(context.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(context.accent, lineWidth: 2))
    }

    static func isSaved(_ option: Option) -> Bool {
        if case .saved = option { return true }
        return false
    }

    /// Saved place: its FavCircles page. Map result: directions in Maps.
    private func go(_ option: Option) {
        context.host.haptic(.success)
        switch option {
        case .saved(let m):
            context.track("whattoeat_lets_go", ["kind": "saved"])
            context.host.openPlace(m.scored.candidate.placeRef)
        case .nearby(let s):
            context.track("whattoeat_lets_go", ["kind": "nearby"])
            var c = URLComponents(string: "https://maps.apple.com/")!
            c.queryItems = [URLQueryItem(name: "daddr", value: "\(s.coordinate.latitude),\(s.coordinate.longitude)"),
                            URLQueryItem(name: "q", value: s.name)]
            if let url = c.url { context.host.openURL(url) }
        }
    }

    private func nearbyRow(_ spot: NearbySpot) -> some View {
        let theme = context.theme
        return Button {
            context.track("whattoeat_choose_nearby")
            context.host.haptic(.selection)
            withAnimation(.spring(response: 0.35)) { pickedPlaceId = Option.nearby(spot).id }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(context.accent).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                    Text(spot.address ?? "On Apple Maps").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
                Spacer()
                if let origin = pool.origin {
                    Text(NextBarFormat.distance(origin.distance(to: spot.coordinate))).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeRow(_ match: CravingPicker.PlaceMatch) -> some View {
        let theme = context.theme
        let candidate = match.scored.candidate
        let picked = pickedPlaceId == candidate.id
        return Button {
            context.track("whattoeat_open_place", ["matched": match.matchesCuisine ? "1" : "0"])
            context.host.openPlace(candidate.placeRef)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: picked ? "star.fill" : (match.matchesCuisine ? "fork.knife" : "bookmark.fill"))
                    .foregroundStyle(context.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.system(size: 15, weight: picked ? .bold : .medium))
                        .foregroundStyle(theme.label).lineLimit(1)
                    Text(NextBarFormat.attribution(candidate.source, savedBy: candidate.savedByName, savers: candidate.savers))
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                if pool.origin != nil {
                    Text(NextBarFormat.distance(match.scored.distanceMeters)).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, picked ? 8 : 0)
            .background(RoundedRectangle(cornerRadius: 10).fill(picked ? context.accent.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var distancePicker: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("How far will you go?", theme: theme)
            Picker("Max distance", selection: Binding(
                get: { state.model.maxDistanceMeters },
                set: { meters in state.update { $0.maxDistanceMeters = meters } }
            )) {
                ForEach(distanceChoices, id: \.meters) { Text($0.label).tag($0.meters) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// "an Italian spot", "a Thai spot".
    static func article(for word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    private func pickForMe(from options: [Option]) {
        // Nearer is likelier (same weighting as NextBar), never the current pick again
        let fresh = options.filter { $0.id != pickedPlaceId }
        guard !fresh.isEmpty else { return }
        let weights = fresh.map { option -> Double in
            switch option {
            case .saved(let m): return NextBarPicker.weight(distanceMeters: m.scored.distanceMeters)
            case .nearby(let s): return NextBarPicker.weight(distanceMeters: pool.origin.map { $0.distance(to: s.coordinate) } ?? 0)
            }
        }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var chosen = fresh[fresh.count - 1]
        for (option, w) in zip(fresh, weights) { if roll < w { chosen = option; break }; roll -= w }
        context.track("whattoeat_pick_place")
        context.host.haptic(.success)
        withAnimation(.spring(response: 0.35)) { pickedPlaceId = chosen.id }
    }
}

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Mode", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if tab == .spin { spinTab } else { placeTab }
            }
            .padding(16)
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
                let c = CravingLibrary.all.randomElement()!
                reel = (c.emoji, c.name)
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

    private var placeTab: some View {
        let theme = context.theme
        let cuisine = state.model.currentCuisine
        let matches = pool.matches(for: state.model)
        let matching = matches.filter(\.matchesCuisine)
        return VStack(alignment: .leading, spacing: 16) {
            if let cuisine, let dish = state.model.currentDish {
                Text("\(cuisine.emoji) Craving \(cuisine.name): \(dish)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.label)
            }
            switch pool.status {
            case .loading, .idle:
                HStack(spacing: 8) { ProgressView(); Text("Finding saved restaurants near you…") }
                    .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            case .failed(let message):
                Text(message).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            case .loaded:
                if matches.isEmpty {
                    Text(pool.locationDenied
                         ? "Turn on location for FavCircles to see restaurants near you."
                         : "No saved restaurants in range. Widen the distance, or save a few restaurants to your circles.")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                } else {
                    if let cuisine, matching.isEmpty {
                        Text("No saved \(cuisine.name) spots nearby. Here are favorites close by instead.")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                    WidgetUI.primaryButton(matching.isEmpty ? "Pick one for me" : "Pick a \(cuisine?.name ?? "") spot for me", color: context.accent) {
                        pickForMe(from: matching.isEmpty ? matches : matching)
                    }
                    ForEach(Array(matches.prefix(20)), id: \.scored.candidate.id) { match in
                        placeRow(match)
                        Divider().overlay(theme.separator)
                    }
                }
            }
            distancePicker
        }
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

    private func pickForMe(from options: [CravingPicker.PlaceMatch]) {
        let scored = options.map(\.scored)
        guard let chosen = NextBarPicker.pick(from: scored, excluding: pickedPlaceId.map { [$0] } ?? []) else { return }
        context.track("whattoeat_pick_place")
        context.host.haptic(.success)
        withAnimation(.spring(response: 0.35)) { pickedPlaceId = chosen.candidate.id }
    }
}

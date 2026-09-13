import SwiftUI
import FavWidgetsCore

struct NextBarFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<NextBarSettings>
    @ObservedObject var pool: NextBarPool
    @ObservedObject var rounds: NextBarRoundsStore
    @State private var showAllVisits = false
    @State private var showStartRound = false

    private let distanceChoices: [(label: String, meters: Double)] = [
        ("1 km", 1_000), ("3 km", 3_000), ("10 km", 10_000), ("Any", 100_000)
    ]

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WidgetSyncBadge(state: state.syncState, theme: theme)
                roundsSection
                pickSection
                poolSection
                settingsSection
                visitsSection
            }
            .padding(16)
        }
        .background(theme.background)
        .refreshable {
            await pool.reload()
            await rounds.refresh()
        }
        .task {
            await state.loadIfNeeded()
            await rounds.loadIfNeeded()
            await pool.loadIfNeeded()
            rounds.startPolling()
        }
        .onDisappear { rounds.stopPolling() }
        .sheet(isPresented: $showStartRound) {
            NextBarStartRoundView(context: context, pool: pool, state: state, store: rounds) { showStartRound = false }
        }
    }

    // MARK: - Vote with friends

    private var roundsSection: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                WidgetUI.header("Vote with friends", theme: theme)
                Spacer()
                Button { startRound() } label: {
                    Label("Start a vote", systemImage: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(context.accent))
                }
                .buttonStyle(.plain)
                .disabled(pool.status != .loaded || pool.scored(for: state.model).count < 2)
            }
            if let error = rounds.errorMessage, rounds.rounds.isEmpty {
                Text(error).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(rounds.openRounds) { round in
                NextBarRoundView(context: context, round: round, store: rounds) { letsGo(option: $0) }
            }
            ForEach(rounds.recentResults) { round in
                NextBarRoundView(context: context, round: round, store: rounds) { letsGo(option: $0) }
            }
            if rounds.hasLoaded && rounds.openRounds.isEmpty && rounds.recentResults.isEmpty {
                Text("Let the app pick a few options, tag who you're with, and everyone votes.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    private func startRound() {
        context.track("nextbar_start_round_tapped")
        showStartRound = true
    }

    private func letsGo(option: NextBarRound.Option) {
        context.track("nextbar_lets_go", ["source": "round"])
        context.host.haptic(.success)
        state.update {
            $0.visits.append(NextBarVisit(placeId: option.placeId, name: option.name, source: option.sourceValue,
                                          savedByName: option.savers?.first, savers: option.savers,
                                          distanceMeters: option.distanceMeters ?? 0))
        }
        context.host.openPlace(option.placeRef)
    }

    // MARK: - Tonight

    private var currentPick: NextBarPick? {
        guard let pick = state.model.currentPick, pick.day == context.today else { return nil }
        return pick
    }

    private var pickSection: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Tonight", theme: theme)
            if let pick = currentPick {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pick.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(theme.label)
                    Text("\(NextBarFormat.distance(pick.distanceMeters)) away · \(NextBarFormat.attribution(pick.source, savedBy: pick.savedByName, savers: pick.savers))")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.secondaryLabel)
                    if let address = pool.candidate(id: pick.placeId)?.address, !address.isEmpty {
                        Text(address).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                HStack(spacing: 10) {
                    Button { letsGo(pick) } label: {
                        Label("Let's go", systemImage: "figure.walk")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent))
                    }
                    .buttonStyle(.plain)
                    Button { shuffle() } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(context.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
                Button("Open in FavCircles") { openPick(pick) }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.primary)
            } else {
                emptyPickState
            }
        }
    }

    private var emptyPickState: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            switch pool.status {
            case .loading:
                HStack(spacing: 8) { ProgressView(); Text("Finding bars near you…") }
                    .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            case .failed(let message):
                Text(message).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            default:
                if pool.candidates.isEmpty {
                    Text("No bars yet. Save a few bars to your circles, or connect with people who have — their bars count too.")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                } else if pool.scored(for: state.model).isEmpty {
                    Text(pool.locationDenied
                         ? "Turn on location for FavCircles to get a pick near you."
                         : "Nothing within \(NextBarFormat.distance(state.model.maxDistanceMeters)). Widen the distance below.")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                } else {
                    Text("Ready when you are.").font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                }
            }
            if pool.status == .loaded && !pool.scored(for: state.model).isEmpty {
                WidgetUI.primaryButton("Pick tonight's bar", color: context.accent) { shuffle() }
            }
        }
    }

    // MARK: - Nearby pool

    private var poolSection: some View {
        let theme = context.theme
        let scored = Array(pool.scored(for: state.model).prefix(15))
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("In range (\(pool.scored(for: state.model).count))", theme: theme)
            if scored.isEmpty {
                Text(pool.status == .loaded ? "No bars in range." : " ")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(scored, id: \.candidate.id) { item in
                Button { choose(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: item.candidate.source))
                            .foregroundStyle(context.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.candidate.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                            Text(NextBarFormat.attribution(item.candidate.source, savedBy: item.candidate.savedByName, savers: item.candidate.savers))
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        Text(pool.origin == nil ? "" : NextBarFormat.distance(item.distanceMeters))
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Divider().overlay(theme.separator)
            }
        }
    }

    private func icon(for source: WidgetPlaceSource) -> String {
        switch source {
        case .mine: return "bookmark.fill"
        case .connection: return "person.2.fill"
        case .following: return "person.crop.circle.badge.checkmark"
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Pick from", theme: theme)
            ForEach(WidgetPlaceSource.allCases, id: \.self) { source in
                Toggle(source.label, isOn: Binding(
                    get: { state.model.sources.contains(source) },
                    set: { on in
                        state.update { settings in
                            if on { settings.sources.insert(source) } else if settings.sources.count > 1 { settings.sources.remove(source) }
                        }
                    }
                ))
                .tint(context.accent)
                .font(.system(size: 15))
            }
            WidgetUI.header("Max distance", theme: theme)
            Picker("Max distance", selection: Binding(
                get: { state.model.maxDistanceMeters },
                set: { meters in state.update { $0.maxDistanceMeters = meters } }
            )) {
                ForEach(distanceChoices, id: \.meters) { choice in Text(choice.label).tag(choice.meters) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - History

    private var visitsSection: some View {
        let theme = context.theme
        let visits = state.model.visits.sorted { $0.date > $1.date }
        let shown = showAllVisits ? visits : Array(visits.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Where you went", theme: theme)
            if visits.isEmpty {
                Text("Tap \"Let's go\" on a pick and it lands here.").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(shown) { visit in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label)
                        Text(NextBarFormat.attribution(visit.source, savedBy: visit.savedByName, savers: visit.savers)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                    Text(visit.date, style: .date).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                .padding(.vertical, 4)
            }
            if visits.count > 5 {
                Button(showAllVisits ? "Show fewer" : "Show all \(visits.count)") { showAllVisits.toggle() }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.primary)
            }
        }
    }

    // MARK: - Actions

    private func shuffle() {
        context.track("nextbar_shuffle")
        context.host.haptic(.light)
        _ = pool.roll(into: state, today: context.today)
    }

    private func choose(_ item: NextBarPicker.Scored) {
        context.track("nextbar_choose")
        context.host.haptic(.selection)
        let pick = NextBarPick(day: context.today, placeId: item.candidate.id, name: item.candidate.name,
                               source: item.candidate.source, savedByName: item.candidate.savedByName,
                               savers: item.candidate.savers, distanceMeters: item.distanceMeters)
        state.update { $0.notePick(pick) }
    }

    private func letsGo(_ pick: NextBarPick) {
        context.track("nextbar_lets_go", ["source": pick.source.rawValue])
        context.host.haptic(.success)
        state.update {
            $0.visits.append(NextBarVisit(placeId: pick.placeId, name: pick.name, source: pick.source,
                                          savedByName: pick.savedByName, savers: pick.savers, distanceMeters: pick.distanceMeters))
        }
        openPick(pick)
    }

    private func openPick(_ pick: NextBarPick) {
        context.track("nextbar_open_place")
        let ref = pool.candidate(id: pick.placeId)?.placeRef ?? WidgetPlaceRef(id: pick.placeId, name: pick.name)
        context.host.openPlace(ref)
    }
}

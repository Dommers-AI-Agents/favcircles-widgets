import SwiftUI
import FavWidgetsCore

/// One voting round: options with live counts, tap to vote, the host's
/// Close button, and the winner once it's decided.
struct NextBarRoundView: View {
    let context: WidgetContext
    let round: NextBarRound
    @ObservedObject var store: NextBarRoundsStore
    let onLetsGo: (NextBarRound.Option) -> Void
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.isHost ? "Your vote" : "\(round.hostName)'s vote")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Text(round.isOpen
                         ? "\(round.votedCount) of \(round.participants.count) voted · \(participantNames)"
                         : "Closed · \(round.votedCount) of \(round.participants.count) voted")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                        .lineLimit(2)
                }
                Spacer()
                if round.isOpen && round.isHost {
                    Button("Close vote") { close() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(context.accent)
                        .disabled(busy)
                }
            }
            ForEach(round.options) { option in
                optionRow(option)
            }
            if let winner = round.winner {
                HStack(spacing: 10) {
                    Text("🏆 It's \(winner.name)!")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    Button { onLetsGo(winner) } label: {
                        Label("Let's go", systemImage: "figure.walk")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(context.accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private var participantNames: String {
        round.participants.map { $0.voted ? "\($0.name) ✓" : $0.name }.joined(separator: ", ")
    }

    private func optionRow(_ option: NextBarRound.Option) -> some View {
        let theme = context.theme
        let isMine = round.myVote == option.placeId
        let isWinner = round.winnerPlaceId == option.placeId
        return Button { vote(option) } label: {
            HStack(spacing: 10) {
                Image(systemName: isMine ? "checkmark.circle.fill" : (isWinner ? "trophy.fill" : "circle"))
                    .foregroundStyle(isMine || isWinner ? context.accent : theme.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                    Text(subtitle(option)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
                Spacer()
                Text("\(option.votes)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(option.votes > 0 ? theme.label : theme.secondaryLabel)
                    .frame(minWidth: 20)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!round.isOpen || busy)
    }

    private func subtitle(_ option: NextBarRound.Option) -> String {
        var parts: [String] = []
        if let d = option.distanceMeters { parts.append(NextBarFormat.distance(d)) }
        parts.append(NextBarAttribution.text(savers: option.savers ?? [], fallbackSource: option.sourceValue))
        if !option.voters.isEmpty { parts.append(option.voters.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func vote(_ option: NextBarRound.Option) {
        guard round.isOpen, !busy else { return }
        busy = true
        context.host.haptic(.selection)
        context.track("nextbar_vote")
        Task {
            do { try await store.vote(round, placeId: option.placeId) }
            catch { context.host.presentAlert(WidgetAlert(title: "Couldn't vote", message: error.localizedDescription)) }
            busy = false
        }
    }

    private func close() {
        guard !busy else { return }
        busy = true
        context.track("nextbar_round_closed")
        Task {
            do { try await store.close(round) }
            catch { context.host.presentAlert(WidgetAlert(title: "Couldn't close the vote", message: error.localizedDescription)) }
            busy = false
        }
    }
}

/// Compose a round: three proximity-weighted picks (swap or reroll any),
/// tag the connections you're with, start.
struct NextBarStartRoundView: View {
    let context: WidgetContext
    @ObservedObject var pool: NextBarPool
    @ObservedObject var state: WidgetStateController<NextBarSettings>
    @ObservedObject var store: NextBarRoundsStore
    let onDone: () -> Void

    @State private var options: [NextBarPicker.Scored] = []
    @State private var contacts: [WidgetContact] = []
    @State private var contactsError: String?
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var isStarting = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            List {
                Section {
                    ForEach(options, id: \.candidate.id) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.candidate.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label)
                                Text("\(pool.origin == nil ? "" : NextBarFormat.distance(item.distanceMeters) + " · ")\(NextBarAttribution.text(savers: item.candidate.savers, fallbackSource: item.candidate.source, fallbackName: item.candidate.savedByName))")
                                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                            }
                            Spacer()
                            Button { swap(item) } label: { Image(systemName: "arrow.2.squarepath").foregroundStyle(context.accent) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button { reroll() } label: { Label("Reroll all", systemImage: "shuffle") }.foregroundStyle(context.accent)
                } header: {
                    Text("Options (\(options.count))")
                } footer: {
                    Text("Random, weighted toward what's closest. Swap any you don't like.")
                }
                Section {
                    if let contactsError {
                        Text(contactsError).foregroundStyle(theme.secondaryLabel)
                        Button("Retry") { Task { await loadContacts() } }
                    } else if contacts.isEmpty {
                        Text("No connections yet").foregroundStyle(theme.secondaryLabel)
                    }
                    ForEach(filteredContacts) { contact in
                        Button { toggle(contact) } label: {
                            HStack {
                                Text(contact.displayName).foregroundStyle(theme.label)
                                Spacer()
                                if selected.contains(contact.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(context.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Who's with you? (\(selected.count)/10)")
                }
            }
            .searchable(text: $search, prompt: "Search connections")
            .widgetInlineNavigationTitle("Start a vote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isStarting ? "Starting…" : "Start") { start() }
                        .disabled(isStarting || options.count < 2 || selected.isEmpty)
                }
            }
        }
        .task {
            if options.isEmpty { reroll() }
            await loadContacts()
        }
    }

    private var filteredContacts: [WidgetContact] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? contacts : contacts.filter { $0.displayName.lowercased().contains(q) }
    }

    private func loadContacts() async {
        do {
            contacts = try await context.host.fetchConnections().sorted { $0.displayName < $1.displayName }
            contactsError = nil
        } catch {
            contactsError = "Couldn't load your connections"
        }
    }

    private func toggle(_ contact: WidgetContact) {
        if selected.contains(contact.id) { selected.remove(contact.id) }
        else if selected.count < 10 { selected.insert(contact.id) }
    }

    private func reroll() {
        let scored = pool.scored(for: state.model)
        var picked: [NextBarPicker.Scored] = []
        var exclude: [String] = []
        for _ in 0..<min(3, scored.count) {
            guard let next = NextBarPicker.pick(from: scored, excluding: exclude) else { break }
            picked.append(next)
            exclude.append(next.candidate.id)
        }
        options = picked
    }

    private func swap(_ item: NextBarPicker.Scored) {
        let scored = pool.scored(for: state.model)
        let exclude = options.map(\.candidate.id)
        guard scored.count > options.count,
              let replacement = NextBarPicker.pick(from: scored.filter { !exclude.contains($0.candidate.id) }, excluding: []) else { return }
        options = options.map { $0.candidate.id == item.candidate.id ? replacement : $0 }
    }

    private func start() {
        isStarting = true
        context.track("nextbar_round_started", ["options": "\(options.count)", "people": "\(selected.count)"])
        let draft = NextBarRound.Draft(
            participantIds: Array(selected),
            options: options.map { item in
                NextBarRound.Draft.Option(
                    placeId: item.candidate.id, name: item.candidate.name, address: item.candidate.address,
                    source: item.candidate.source.rawValue,
                    savers: item.candidate.savers.isEmpty ? (item.candidate.savedByName.map { [$0] } ?? []) : item.candidate.savers,
                    distanceMeters: item.distanceMeters,
                    lat: item.candidate.coordinate.latitude, lng: item.candidate.coordinate.longitude,
                    isGlobal: item.candidate.isGlobal)
            },
            expiresInMinutes: 180
        )
        Task {
            do {
                try await store.create(draft)
                context.host.haptic(.success)
                onDone()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't start the vote", message: error.localizedDescription))
            }
            isStarting = false
        }
    }
}

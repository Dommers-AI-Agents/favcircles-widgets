import SwiftUI
import FavWidgetsCore

/// A voting round as the server describes it (`/api/widgets/nextbar/rounds`).
struct NextBarRound: Codable, Identifiable, Equatable {
    struct Participant: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let voted: Bool
    }

    struct Option: Codable, Equatable, Identifiable {
        let placeId: String
        let name: String
        let address: String?
        let source: String?
        let savers: [String]?
        let distanceMeters: Double?
        let lat: Double?
        let lng: Double?
        let isGlobal: Bool?
        let votes: Int
        let voters: [String]

        var id: String { placeId }
        var placeRef: WidgetPlaceRef { WidgetPlaceRef(id: placeId, name: name, isGlobal: isGlobal ?? true) }
        var sourceValue: WidgetPlaceSource { WidgetPlaceSource(rawValue: source ?? "") ?? .connection }
    }

    let id: String
    let hostId: String
    let hostName: String
    let status: String
    let winnerPlaceId: String?
    let createdAt: Date
    let expiresAt: Date?
    let closedAt: Date?
    let participants: [Participant]
    let options: [Option]
    let myVote: String?
    let isHost: Bool

    var isOpen: Bool { status == "open" }
    var votedCount: Int { participants.filter(\.voted).count }
    var winner: Option? { options.first { $0.placeId == winnerPlaceId } }

    /// Wire payload for creating a round.
    struct Draft: Encodable {
        struct Option: Encodable {
            let placeId: String
            let name: String
            let address: String?
            let source: String
            let savers: [String]
            let distanceMeters: Double
            let lat: Double
            let lng: Double
            let isGlobal: Bool
        }
        let participantIds: [String]
        let options: [Option]
        let expiresInMinutes: Int
    }
}

/// Talks to the rounds endpoints through the host's API channel.
struct NextBarRoundsClient {
    let host: FavWidgetHost

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
        }
        return d
    }()

    private struct ListResponse: Decodable { let rounds: [NextBarRound] }
    private struct SingleResponse: Decodable { let round: NextBarRound }

    func list() async throws -> [NextBarRound] {
        let data = try await host.request(WidgetAPIRequest(.get, "widgets/nextbar/rounds"))
        return try Self.decoder.decode(ListResponse.self, from: data).rounds
    }

    func create(_ draft: NextBarRound.Draft) async throws -> NextBarRound {
        let body = try JSONEncoder().encode(draft)
        let data = try await host.request(WidgetAPIRequest(.post, "widgets/nextbar/rounds", body: body))
        return try Self.decoder.decode(SingleResponse.self, from: data).round
    }

    func vote(roundId: String, placeId: String) async throws -> NextBarRound {
        let body = try JSONEncoder().encode(["placeId": placeId])
        let data = try await host.request(WidgetAPIRequest(.post, "widgets/nextbar/rounds/\(roundId)/vote", body: body))
        return try Self.decoder.decode(SingleResponse.self, from: data).round
    }

    func close(roundId: String) async throws -> NextBarRound {
        let data = try await host.request(WidgetAPIRequest(.post, "widgets/nextbar/rounds/\(roundId)/close"))
        return try Self.decoder.decode(SingleResponse.self, from: data).round
    }
}

/// Session cache of the user's rounds; polls while a round is open and on
/// screen so votes show up without a manual refresh.
@MainActor
final class NextBarRoundsStore: ObservableObject {
    @Published private(set) var rounds: [NextBarRound] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?

    private let client: NextBarRoundsClient
    private var pollTask: Task<Void, Never>?

    init(host: FavWidgetHost) {
        client = NextBarRoundsClient(host: host)
    }

    static func shared(in context: WidgetContext) -> NextBarRoundsStore {
        context.transient("nextbar.rounds") { NextBarRoundsStore(host: context.host) }
    }

    var openRounds: [NextBarRound] { rounds.filter(\.isOpen) }

    /// Closed within the last day, so the result is still worth showing.
    var recentResults: [NextBarRound] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return rounds.filter { !$0.isOpen && ($0.closedAt ?? $0.createdAt) > cutoff }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        do {
            rounds = try await client.list()
            errorMessage = nil
        } catch {
            errorMessage = (error as? WidgetAPIError)?.message ?? "Couldn't load votes"
        }
        hasLoaded = true
        isLoading = false
    }

    func create(_ draft: NextBarRound.Draft) async throws {
        let round = try await client.create(draft)
        rounds.insert(round, at: 0)
    }

    func vote(_ round: NextBarRound, placeId: String) async throws {
        replace(try await client.vote(roundId: round.id, placeId: placeId))
    }

    func close(_ round: NextBarRound) async throws {
        replace(try await client.close(roundId: round.id))
    }

    private func replace(_ round: NextBarRound) {
        if let index = rounds.firstIndex(where: { $0.id == round.id }) { rounds[index] = round } else { rounds.insert(round, at: 0) }
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                if !self.openRounds.isEmpty { await self.refresh() }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

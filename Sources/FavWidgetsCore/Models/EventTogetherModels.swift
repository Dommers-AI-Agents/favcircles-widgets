import Foundation

// Events: the things people do together during an event (Wes, 2026-10-06):
// photo challenges, roll call, the shout-out wall, song requests and the
// after-party recap. Shapes as the server sends them; helpers are pure.

public struct EventChallenge: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let emoji: String
    public init(id: String, text: String, emoji: String) { self.id = id; self.text = text; self.emoji = emoji }
}

public struct EventRollCall: Decodable, Equatable, Hashable, Sendable {
    public struct Spot: Decodable, Equatable, Hashable, Sendable {
        public let userId: String
        public let lat: Double
        public let lng: Double
        public let at: String?
    }
    public let id: String
    public let startedAt: String?
    public let startedByName: String
    public let hereIds: [String]
    public let imHere: Bool
    public let locations: [Spot]
}

public struct EventWallPost: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public struct Reaction: Decodable, Equatable, Hashable, Sendable {
        public let emoji: String
        public let count: Int
        public let mine: Bool
    }
    public let id: String
    public let authorId: String
    public let authorName: String
    public let text: String
    public let createdAt: String?
    public let reactions: [Reaction]
    public let canDelete: Bool
}

public struct EventSong: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let addedById: String
    public let addedByName: String
    public let votes: Int
    public let votedByMe: Bool
    public let played: Bool
    public let createdAt: String?
    public let canManage: Bool
}

public struct EventRecap: Decodable, Equatable, Sendable {
    public struct Photo: Decodable, Equatable, Hashable, Sendable {
        public let imageUrl: String
        public let thumbUrl: String?
        public let uploaderName: String
        public let likes: Int
        public var gridURL: String { thumbUrl ?? imageUrl }
    }
    public struct Spot: Decodable, Equatable, Hashable, Sendable { public let name: String; public let lat: Double; public let lng: Double }
    public struct Photographer: Decodable, Equatable, Sendable { public let name: String; public let photos: Int }
    public struct Challenges: Decodable, Equatable, Sendable { public let total: Int; public let done: Int }
    public struct Shoutout: Decodable, Equatable, Sendable { public let text: String; public let authorName: String }
    public struct Song: Decodable, Equatable, Sendable { public let title: String; public let artist: String?; public let votes: Int }

    public let eventId: String
    public let name: String
    public let emoji: String
    public let startedAt: String?
    public let endedAt: String?
    public let memberCount: Int
    public let memberNames: [String]
    public let photoCount: Int
    public let placeCount: Int
    public let topPhotos: [Photo]
    public let photoOfTheNight: Photo?
    public let topPhotographer: Photographer?
    public let places: [Spot]
    public let challenges: Challenges
    public let topShoutout: Shoutout?
    public let topSong: Song?
}

public enum EventTogether {
    /// Challenges you've done (you posted a photo for them).
    public static func doneChallengeIds(photos: [EventPhoto], userId: String) -> Set<String> {
        Set(photos.filter { $0.uploaderId == userId }.compactMap(\.challengeId))
    }

    /// Who hasn't answered the roll call, in member order.
    public static func missing(_ rollCall: EventRollCall, members: [EventSummary.Member]) -> [EventSummary.Member] {
        let here = Set(rollCall.hereIds)
        return members.filter { !here.contains($0.id) }
    }

    /// "5 of 8 here"
    public static func rollCallLine(_ rollCall: EventRollCall, memberCount: Int) -> String {
        let here = min(rollCall.hereIds.count, memberCount)
        return here >= memberCount ? "Everyone's here 🙌" : "\(here) of \(memberCount) here"
    }

    /// One-tap challenges for the coordinator (any kind of event).
    public static let suggestedChallenges: [(emoji: String, text: String)] = [
        ("🤳", "Group selfie"), ("💃", "Best dance move"), ("🍹", "Cheers with someone new"),
        ("🎤", "Sing along moment"), ("😂", "Funniest face"), ("👯", "Matching pose with a friend"),
        ("🌃", "Best view of the night"), ("🍕", "Late-night snack"), ("🏆", "Photo with the guest of honor"),
        ("📍", "Every stop we make")
    ]

    /// "Mr. Brightside · The Killers"
    public static func songLine(_ song: EventSong) -> String {
        song.artist.map { "\(song.title) · \($0)" } ?? song.title
    }
}

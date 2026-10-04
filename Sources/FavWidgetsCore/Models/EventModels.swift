import Foundation

/// The Events widget (Party Bus, Wes 2026-10-04), as the server describes it
/// (`/api/widgets/events`). Photos and places are members-only server-side.
public struct EventSummary: Decodable, Identifiable, Equatable, Sendable {
    public struct Member: Decodable, Identifiable, Equatable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let avatarUrl: String?
        public let isHost: Bool
    }

    public let id: String
    public let name: String
    public let emoji: String
    public let hostId: String
    public let hostName: String
    public let isHost: Bool
    public let joinOpen: Bool
    public let createdAt: String?
    public let photoCount: Int
    public let placeCount: Int
    public let members: [Member]
    /// Invited in the app and not joined yet (older servers omit it)
    public let invited: [Invitee]?
    public let inviteUrl: String
    public let myCircleId: String?

    public var inviteURL: URL? { URL(string: inviteUrl) }
    public var invitedPeople: [Invitee] { invited ?? [] }

    public struct Invitee: Decodable, Identifiable, Equatable, Hashable, Sendable {
        public let id: String
        public let name: String
    }
}

public struct EventPhoto: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let imageUrl: String
    public let uploaderId: String
    public let uploaderName: String
    public let caption: String
    public let createdAt: String?
    public let likeCount: Int
    public let likedByMe: Bool
    public let canDelete: Bool

    public init(id: String, imageUrl: String, uploaderId: String, uploaderName: String, caption: String, createdAt: String?,
                likeCount: Int, likedByMe: Bool, canDelete: Bool) {
        self.id = id; self.imageUrl = imageUrl; self.uploaderId = uploaderId; self.uploaderName = uploaderName
        self.caption = caption; self.createdAt = createdAt; self.likeCount = likeCount; self.likedByMe = likedByMe; self.canDelete = canDelete
    }
}

public struct EventPlace: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let lat: Double
    public let lng: Double
    public let category: String
    public let taggedById: String
    public let taggedByName: String
    public let createdAt: String?
    public let savedCount: Int
    public let savedByMe: Bool
}

public struct EventDetail: Decodable, Equatable, Sendable {
    public let event: EventSummary
    public let photos: [EventPhoto]
    public let places: [EventPlace]

    public init(event: EventSummary, photos: [EventPhoto], places: [EventPlace]) {
        self.event = event
        self.photos = photos
        self.places = places
    }
}

/// The join screen: what a link points at.
public struct EventInvitePreview: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let hostName: String
    public let memberCount: Int
    public let joinOpen: Bool
    public let alreadyMember: Bool
}

/// The words on the Events screens. Pure, so they're tested on a Mac.
public enum EventCopy {
    public static let defaultName = "Party Bus"
    public static let emojiChoices = ["🚌", "🎉", "🍾", "🎂", "💍", "🏖️", "⛳️", "🏈", "🎤", "🥳"]

    public static func memberCount(_ n: Int) -> String {
        n == 1 ? "Just you so far" : "\(n) people"
    }

    /// The text that rides with the invite link in a group message.
    public static func inviteText(_ event: EventSummary) -> String {
        "\(event.emoji) Join \(event.name) on FavCircles! Tap to join, share photos and save the places we go: \(event.inviteUrl)"
    }

    /// The invite sheet's send button: names how many are ticked, never "0".
    public static func inviteButton(selected: Int) -> String {
        selected == 0 ? "Invite" : "Invite \(selected)"
    }

    public static func joinButton(_ preview: EventInvitePreview) -> String {
        "Join \(preview.name) \(preview.emoji)"
    }

    public static func joinedMessage(name: String, coinCredited: Bool) -> String {
        coinCredited ? "You're in \(name)! +1 FavCoin 🌵" : "You're in \(name)!"
    }

    public static func uploadProgress(done: Int, total: Int) -> String {
        total <= 1 ? "Adding your photo…" : "Adding \(min(done + 1, total)) of \(total)…"
    }

    public static func savedToCircle(placeName: String, eventName: String) -> String {
        "\(placeName) is in your \(eventName) circle"
    }

    /// The members of `event` the viewer isn't connected to (for "Connect with everyone").
    public static func notConnected(_ event: EventSummary, myId: String?, connectedIds: Set<String>) -> [EventSummary.Member] {
        event.members.filter { $0.id != myId && !connectedIds.contains($0.id) }
    }
}

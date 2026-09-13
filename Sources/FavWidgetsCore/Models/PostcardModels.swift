import Foundation

/// A postcard being written; the photo stays in memory (too large for a
/// document), everything else survives a relaunch.
public struct PostcardDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var templateId: String
    public var message: String
    public var recipientId: String?
    public var recipientName: String?
    public var place: WidgetPlaceRef?
    public var updatedAt: Date

    public init(id: UUID = UUID(), templateId: String, message: String = "", recipientId: String? = nil,
                recipientName: String? = nil, place: WidgetPlaceRef? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.templateId = templateId
        self.message = message
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.place = place
        self.updatedAt = updatedAt
    }
}

public struct PostcardRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var messageId: String
    public var conversationId: String
    public var recipientId: String
    public var recipientName: String
    public var templateId: String
    public var message: String
    public var imageURL: URL?
    public var place: WidgetPlaceRef?
    public var sentAt: Date

    public init(id: UUID = UUID(), messageId: String, conversationId: String, recipientId: String, recipientName: String,
                templateId: String, message: String, imageURL: URL?, place: WidgetPlaceRef?, sentAt: Date = Date()) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.templateId = templateId
        self.message = message
        self.imageURL = imageURL
        self.place = place
        self.sentAt = sentAt
    }
}

/// Settings document (`postcard`).
public struct PostcardSettings: WidgetModel {
    public var draft: PostcardDraft?
    public var lastTemplateId: String

    public init(draft: PostcardDraft? = nil, lastTemplateId: String = "classic") {
        self.draft = draft
        self.lastTemplateId = lastTemplateId
    }

    public static let empty = PostcardSettings()
}

/// One month of sent postcards (`postcard_yyyy-MM`).
public struct PostcardMonth: WidgetModel {
    public var sent: [PostcardRecord]

    public init(sent: [PostcardRecord] = []) {
        self.sent = sent
    }

    public static let empty = PostcardMonth()

    public static func merge(local: PostcardMonth, remote: PostcardMonth) -> PostcardMonth {
        let known = Set(local.sent.map(\.messageId))
        var merged = local
        merged.sent.append(contentsOf: remote.sent.filter { !known.contains($0.messageId) })
        merged.sent.sort { $0.sentAt < $1.sentAt }
        return merged
    }
}

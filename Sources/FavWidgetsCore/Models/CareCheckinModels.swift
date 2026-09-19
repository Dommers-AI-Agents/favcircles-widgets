import Foundation

// "How Are You?": an adult child sets up a few times a day when a parent
// gets a short question as a push and answers with one tap. Server-owned;
// these are the wire types plus the words.

public enum CareAnswer: String, Codable, CaseIterable, Sendable {
    case great, okay
    case notGreat = "not_great"

    public var label: String {
        switch self {
        case .great: return "Doing great 👍"
        case .okay: return "Okay"
        case .notGreat: return "Not so good"
        }
    }

    public var symbolName: String {
        switch self {
        case .great: return "hand.thumbsup.fill"
        case .okay: return "hand.raised.fill"
        case .notGreat: return "cloud.rain.fill"
        }
    }
}

public struct CareAsk: Decodable, Equatable, Identifiable, Sendable {
    public var askId: String
    public var planId: String
    public var questionText: String
    public var slot: String
    public var dateKey: String
    public var askedAt: Date
    public var dueBy: Date?
    public var status: String
    public var answer: CareAnswer?
    public var answerText: String?
    public var note: String
    public var answeredAt: Date?
    public var pushDelivered: Bool

    public var id: String { askId }
    public var isOpen: Bool { status == "open" }
    public var isMissed: Bool { status == "missed" }

    public init(askId: String, planId: String, questionText: String, slot: String = "08:30", dateKey: String = "", askedAt: Date,
                dueBy: Date? = nil, status: String = "open", answer: CareAnswer? = nil, answerText: String? = nil,
                note: String = "", answeredAt: Date? = nil, pushDelivered: Bool = true) {
        self.askId = askId
        self.planId = planId
        self.questionText = questionText
        self.slot = slot
        self.dateKey = dateKey
        self.askedAt = askedAt
        self.dueBy = dueBy
        self.status = status
        self.answer = answer
        self.answerText = answerText
        self.note = note
        self.answeredAt = answeredAt
        self.pushDelivered = pushDelivered
    }

    private enum CodingKeys: String, CodingKey {
        case askId, planId, questionText, slot, dateKey, askedAt, dueBy, status, answer, answerText, note, answeredAt, pushDelivered
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        askId = try c.decode(String.self, forKey: .askId)
        planId = try c.decode(String.self, forKey: .planId)
        questionText = try c.decodeIfPresent(String.self, forKey: .questionText) ?? ""
        slot = try c.decodeIfPresent(String.self, forKey: .slot) ?? ""
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        askedAt = try c.decode(Date.self, forKey: .askedAt)
        dueBy = try c.decodeIfPresent(Date.self, forKey: .dueBy)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        // An answer value this build doesn't know decodes as nil, never as a crash.
        answer = (try? c.decodeIfPresent(String.self, forKey: .answer)).flatMap { $0 }.flatMap(CareAnswer.init(rawValue:))
        answerText = try c.decodeIfPresent(String.self, forKey: .answerText)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        answeredAt = try c.decodeIfPresent(Date.self, forKey: .answeredAt)
        pushDelivered = try c.decodeIfPresent(Bool.self, forKey: .pushDelivered) ?? true
    }
}

public struct CareQuestion: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// A sibling on someone else's check-in. One child sets the arrangement up and
/// the rest join it, so the parent is asked once rather than once per child.
/// The parent decides who is on this list — agreeing to one person seeing how
/// you are is not agreeing to four.
public struct CareWatcher: Decodable, Equatable, Identifiable, Sendable {
    public var userId: String
    public var name: String
    /// "invited" (waiting on the parent) or "active".
    public var status: String
    public var invitedBy: String?
    public var acceptedAt: Date?

    public var id: String { userId }
    public var isPending: Bool { status == "invited" }

    public init(userId: String, name: String, status: String, invitedBy: String? = nil, acceptedAt: Date? = nil) {
        self.userId = userId
        self.name = name
        self.status = status
        self.invitedBy = invitedBy
        self.acceptedAt = acceptedAt
    }
}

public struct CarePlan: Decodable, Equatable, Identifiable, Sendable {
    public var planId: String
    /// "owner" (the child who set it up), "parent" (the one being asked),
    /// "watcher" (a sibling the parent let in) or "pending_watcher".
    public var role: String
    public var ownerId: String
    public var ownerName: String
    public var parentId: String
    public var parentName: String
    /// invited · active · paused · declined
    public var status: String
    public var questions: [CareQuestion]
    public var usesDefaultQuestions: Bool
    public var defaultQuestions: [String]
    /// "HH:mm" in the parent's zone.
    public var times: [String]
    public var timezone: String?
    public var createdAt: Date?
    public var acceptedAt: Date?
    public var lastAskedAt: Date?
    public var lastAnsweredAt: Date?
    public var openAsk: CareAsk?
    public var lastAnswer: CareAsk?
    public var watchers: [CareWatcher]

    public var id: String { planId }
    public var isOwner: Bool { role == "owner" }
    /// Reads the answers but never changes the schedule.
    public var isWatcher: Bool { role == "watcher" }
    public var isParent: Bool { role == "parent" }
    /// Siblings waiting on this parent to say yes.
    public var pendingWatchers: [CareWatcher] { watchers.filter(\.isPending) }
    public var activeWatchers: [CareWatcher] { watchers.filter { $0.status == "active" } }
    public var isInvited: Bool { status == "invited" }
    public var isActive: Bool { status == "active" }
    public var isPaused: Bool { status == "paused" }
    /// The other person, from the viewer's side.
    public var otherName: String { isOwner ? parentName : ownerName }

    public init(planId: String, role: String, ownerId: String, ownerName: String, parentId: String, parentName: String,
                status: String, questions: [CareQuestion] = [], usesDefaultQuestions: Bool = true, defaultQuestions: [String] = [],
                times: [String] = ["08:30", "13:00", "19:00"], timezone: String? = nil, createdAt: Date? = nil, acceptedAt: Date? = nil,
                lastAskedAt: Date? = nil, lastAnsweredAt: Date? = nil, openAsk: CareAsk? = nil, lastAnswer: CareAsk? = nil,
                watchers: [CareWatcher] = []) {
        self.planId = planId
        self.role = role
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.parentId = parentId
        self.parentName = parentName
        self.status = status
        self.questions = questions
        self.usesDefaultQuestions = usesDefaultQuestions
        self.defaultQuestions = defaultQuestions
        self.times = times
        self.timezone = timezone
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
        self.lastAskedAt = lastAskedAt
        self.lastAnsweredAt = lastAnsweredAt
        self.openAsk = openAsk
        self.lastAnswer = lastAnswer
        self.watchers = watchers
    }

    enum CodingKeys: String, CodingKey {
        case planId, role, ownerId, ownerName, parentId, parentName, status, questions
        case usesDefaultQuestions, defaultQuestions, times, timezone, createdAt, acceptedAt
        case lastAskedAt, lastAnsweredAt, openAsk, lastAnswer, watchers
    }

    // Hand-written so a field the server has not shipped yet is a default
    // rather than a decode failure. A widget that refuses to parse is a blank
    // screen, and this one is how a family finds out a parent went quiet.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planId = try c.decode(String.self, forKey: .planId)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "owner"
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName) ?? ""
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId) ?? ""
        parentName = try c.decodeIfPresent(String.self, forKey: .parentName) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "invited"
        questions = try c.decodeIfPresent([CareQuestion].self, forKey: .questions) ?? []
        usesDefaultQuestions = try c.decodeIfPresent(Bool.self, forKey: .usesDefaultQuestions) ?? true
        defaultQuestions = try c.decodeIfPresent([String].self, forKey: .defaultQuestions) ?? []
        times = try c.decodeIfPresent([String].self, forKey: .times) ?? ["08:30", "13:00", "19:00"]
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        acceptedAt = try c.decodeIfPresent(Date.self, forKey: .acceptedAt)
        lastAskedAt = try c.decodeIfPresent(Date.self, forKey: .lastAskedAt)
        lastAnsweredAt = try c.decodeIfPresent(Date.self, forKey: .lastAnsweredAt)
        openAsk = try c.decodeIfPresent(CareAsk.self, forKey: .openAsk)
        lastAnswer = try c.decodeIfPresent(CareAsk.self, forKey: .lastAnswer)
        watchers = try c.decodeIfPresent([CareWatcher].self, forKey: .watchers) ?? []
    }
}

/// Both halves of the widget's world in one read.
public struct CarePlans: Decodable, Equatable, Sendable {
    public var asOwner: [CarePlan]
    public var asParent: [CarePlan]
    /// Plans someone else set up that this person was let in on.
    public var asWatcher: [CarePlan]

    public init(asOwner: [CarePlan] = [], asParent: [CarePlan] = [], asWatcher: [CarePlan] = []) {
        self.asOwner = asOwner
        self.asParent = asParent
        self.asWatcher = asWatcher
    }

    enum CodingKeys: String, CodingKey { case asOwner, asParent, asWatcher }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOwner = try c.decodeIfPresent([CarePlan].self, forKey: .asOwner) ?? []
        asParent = try c.decodeIfPresent([CarePlan].self, forKey: .asParent) ?? []
        asWatcher = try c.decodeIfPresent([CarePlan].self, forKey: .asWatcher) ?? []
    }

    public var isEmpty: Bool { asOwner.isEmpty && asParent.isEmpty && asWatcher.isEmpty }
    /// Everything this person follows, however they came to it.
    public var following: [CarePlan] { asOwner + asWatcher }
    /// Invitations waiting on this person, then open questions for them.
    public var invitations: [CarePlan] { asParent.filter(\.isInvited) }
    public var openAsks: [(plan: CarePlan, ask: CareAsk)] {
        asParent.compactMap { plan in plan.openAsk.map { (plan, $0) } }
    }
}

public enum CareCopy {
    public static let defaultTimes = ["08:30", "13:00", "19:00"]
    public static let timeChoices: [String] = stride(from: 6, through: 22, by: 1).flatMap { h in ["00", "30"].map { String(format: "%02d:%@", h, $0) } }

    /// "08:30" → "8:30 AM" in the viewer's locale style.
    public static func friendlyTime(_ hhmm: String, locale: Locale = .current) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        var comps = DateComponents()
        comps.hour = parts[0]
        comps.minute = parts[1]
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps) else { return hhmm }
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .none
        f.timeStyle = .short
        return plainSpaces(f.string(from: date))
    }

    /// Newer systems put a narrow no-break space before AM/PM; one kind of
    /// space keeps copy (and tests) predictable.
    static func plainSpaces(_ s: String) -> String { s.plainSpaces }

    /// "8:30 AM, 1:00 PM and 7:00 PM"
    public static func timesLine(_ times: [String], locale: Locale = .current) -> String {
        let pretty = times.map { friendlyTime($0, locale: locale) }
        if pretty.count <= 1 { return pretty.first ?? "" }
        return pretty.dropLast().joined(separator: ", ") + " and " + pretty.last!
    }

    /// One line on the card. The person being asked sees their question
    /// first; the person checking sees the latest answer or the silence.
    public static func cardSummary(_ plans: CarePlans?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let plans, !plans.isEmpty else { return "Check on Mom or Dad, a few times a day" }
        if let invite = plans.invitations.first { return "\(invite.ownerName) wants to check in on you" }
        if let open = plans.openAsks.first { return "\(open.plan.ownerName) asks: \(open.ask.questionText)" }
        if let owned = plans.asOwner.first {
            return ownerLine(owned, now: now, calendar: calendar)
        }
        if let parent = plans.asParent.first {
            return parent.isActive ? "\(parent.ownerName) checks in on you · all answered" : "\(parent.ownerName) · \(parent.status)"
        }
        return "Check on Mom or Dad, a few times a day"
    }

    /// "Mom: Doing great 👍 · 9:02 AM", "Mom hasn't answered since 8:30 AM", "Waiting for Mom to accept".
    public static func ownerLine(_ plan: CarePlan, now: Date = Date(), calendar: Calendar = .current) -> String {
        if plan.isInvited { return "Waiting for \(plan.parentName) to accept" }
        if plan.status == "declined" { return "\(plan.parentName) declined" }
        if plan.isPaused { return "\(plan.parentName) · paused" }
        if let open = plan.openAsk {
            if let due = open.dueBy, due <= now { return "\(plan.parentName) hasn't answered since \(friendlyTime(open.slot))" }
            return "Asked \(plan.parentName) at \(friendlyTime(open.slot)) · waiting"
        }
        if let last = plan.lastAnswer, let text = last.answerText, let at = last.answeredAt {
            return "\(plan.parentName): \(text) · \(relative(at, now: now, calendar: calendar))"
        }
        return "\(plan.parentName) · no answers yet"
    }

    /// "9:02 AM" today, "yesterday 7:10 PM", or "Sep 12".
    public static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        WidgetDateCopy.dayTime(date, now: now, calendar: calendar)
    }

    /// The status chip on a plan row.
    public static func statusChip(_ plan: CarePlan) -> String {
        switch plan.status {
        case "invited": return "Invited"
        case "active": return "Active"
        case "paused": return "Paused"
        case "declined": return "Declined"
        default: return plan.status.capitalized
        }
    }
}

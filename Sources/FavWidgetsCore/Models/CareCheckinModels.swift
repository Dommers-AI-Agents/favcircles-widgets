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

/// What kind of answer a question takes. The kind decides the buttons on the
/// Lock Screen and the control in the widget; the server sends one push type
/// per kind. A kind this build doesn't know decodes as `.unknown` and is
/// answered in the widget with the mood buttons — never a blank screen.
public enum CareQuestionKind: String, Codable, CaseIterable, Sendable {
    /// Doing great 👍 / Okay / Not so good
    case mood
    /// Yes / Not yet / No — "did you … today?"
    case done
    /// Yes / No — a state, not a task
    case yesno
    /// 0–10 with a low and a high label
    case scale
    /// A few typed words
    case text
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CareQuestionKind(rawValue: raw) ?? .unknown
    }

    /// The choice keys and labels for the choice kinds, in button order.
    public var choices: [(key: String, label: String)] {
        switch self {
        case .mood, .unknown: return CareAnswer.allCases.map { ($0.rawValue, $0.label) }
        case .done: return [("yes", "Yes"), ("not_yet", "Not yet"), ("no", "No")]
        case .yesno: return [("yes", "Yes"), ("no", "No")]
        case .scale, .text: return []
        }
    }

    /// One word for the owner's rotation list.
    public var label: String {
        switch self {
        case .mood, .unknown: return "Mood"
        case .done: return "Yes / not yet / no"
        case .yesno: return "Yes / no"
        case .scale: return "0 to 10"
        case .text: return "In their words"
        }
    }

    public var symbolName: String {
        switch self {
        case .mood, .unknown: return "face.smiling"
        case .done: return "checkmark.circle"
        case .yesno: return "questionmark.circle"
        case .scale: return "slider.horizontal.3"
        case .text: return "text.bubble"
        }
    }

    /// The kinds an owner can give a question of their own.
    public static let pickable: [CareQuestionKind] = [.yesno, .done, .scale, .text, .mood]
}

/// What the parent sends back. Built by the widget, posted by CareAPI.
public enum CareAnswerPayload: Equatable, Sendable {
    case choice(String)
    case scale(Int)
    case text(String)

    /// The request body: a choice goes as `answer`, a number or words as `value`.
    public func body(note: String) -> [String: Any] {
        switch self {
        case .choice(let key): return ["answer": key, "note": note]
        case .scale(let n): return ["value": n, "note": note]
        case .text(let words): return ["value": words, "note": note]
        }
    }

    /// The analytics word for the answer.
    public var trackingValue: String {
        switch self {
        case .choice(let key): return key
        case .scale(let n): return String(n)
        case .text: return "text"
        }
    }
}

public struct CareAsk: Decodable, Equatable, Identifiable, Sendable {
    public var askId: String
    public var planId: String
    public var questionText: String
    public var kind: CareQuestionKind
    /// Scale questions: the one-word name ("Pain") and the end labels.
    public var short: String?
    public var low: String?
    public var high: String?
    public var slot: String
    public var dateKey: String
    public var askedAt: Date
    public var dueBy: Date?
    public var status: String
    /// The mood answer, for the original three-button questions.
    public var answer: CareAnswer?
    /// The raw answer as a string for every kind: a choice key, "7", or the words.
    public var answerValue: String?
    /// The number, for 0–10 questions.
    public var answerScore: Int?
    /// Always the words to show.
    public var answerText: String?
    /// The server flagged this answer as one the family should notice.
    public var alert: Bool
    public var note: String
    public var answeredAt: Date?
    public var pushDelivered: Bool

    public var id: String { askId }
    public var isOpen: Bool { status == "open" }
    public var isMissed: Bool { status == "missed" }
    public var isAnswered: Bool { status == "answered" }

    public init(askId: String, planId: String, questionText: String, kind: CareQuestionKind = .mood, short: String? = nil,
                low: String? = nil, high: String? = nil, slot: String = "08:30", dateKey: String = "", askedAt: Date,
                dueBy: Date? = nil, status: String = "open", answer: CareAnswer? = nil, answerValue: String? = nil,
                answerScore: Int? = nil, answerText: String? = nil, alert: Bool = false,
                note: String = "", answeredAt: Date? = nil, pushDelivered: Bool = true) {
        self.askId = askId
        self.planId = planId
        self.questionText = questionText
        self.kind = kind
        self.short = short
        self.low = low
        self.high = high
        self.slot = slot
        self.dateKey = dateKey
        self.askedAt = askedAt
        self.dueBy = dueBy
        self.status = status
        self.answer = answer
        self.answerValue = answerValue ?? answer?.rawValue
        self.answerScore = answerScore
        self.answerText = answerText
        self.alert = alert
        self.note = note
        self.answeredAt = answeredAt
        self.pushDelivered = pushDelivered
    }

    private enum CodingKeys: String, CodingKey {
        case askId, planId, questionText, kind, short, low, high, slot, dateKey, askedAt, dueBy, status
        case answer, answerValue, answerScore, answerText, alert, note, answeredAt, pushDelivered
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        askId = try c.decode(String.self, forKey: .askId)
        planId = try c.decode(String.self, forKey: .planId)
        questionText = try c.decodeIfPresent(String.self, forKey: .questionText) ?? ""
        // A server that predates kinds sent only mood questions.
        kind = try c.decodeIfPresent(CareQuestionKind.self, forKey: .kind) ?? .mood
        short = try c.decodeIfPresent(String.self, forKey: .short)
        low = try c.decodeIfPresent(String.self, forKey: .low)
        high = try c.decodeIfPresent(String.self, forKey: .high)
        slot = try c.decodeIfPresent(String.self, forKey: .slot) ?? ""
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        askedAt = try c.decode(Date.self, forKey: .askedAt)
        dueBy = try c.decodeIfPresent(Date.self, forKey: .dueBy)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        // An answer value this build doesn't know decodes as nil, never as a crash.
        answer = (try? c.decodeIfPresent(String.self, forKey: .answer)).flatMap { $0 }.flatMap(CareAnswer.init(rawValue:))
        answerValue = try c.decodeIfPresent(String.self, forKey: .answerValue) ?? answer?.rawValue
        answerScore = try c.decodeIfPresent(Int.self, forKey: .answerScore)
        answerText = try c.decodeIfPresent(String.self, forKey: .answerText)
        alert = try c.decodeIfPresent(Bool.self, forKey: .alert) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        answeredAt = try c.decodeIfPresent(Date.self, forKey: .answeredAt)
        pushDelivered = try c.decodeIfPresent(Bool.self, forKey: .pushDelivered) ?? true
    }
}

public struct CareQuestion: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var kind: CareQuestionKind
    public var short: String?
    public var low: String?
    public var high: String?
    /// "bank" (comes with the profile) or "custom" (the owner wrote it).
    public var source: String
    /// A bank question the owner switched off.
    public var muted: Bool
    /// "Daily", "Every 3 days", "Weekly · Fridays".
    public var cadence: String
    /// The profile flag that put it in rotation, if any.
    public var requires: String?

    public var isCustom: Bool { source == "custom" }

    public init(id: String, text: String, kind: CareQuestionKind = .mood, short: String? = nil, low: String? = nil, high: String? = nil,
                source: String = "custom", muted: Bool = false, cadence: String = "Daily", requires: String? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.short = short
        self.low = low
        self.high = high
        self.source = source
        self.muted = muted
        self.cadence = cadence
        self.requires = requires
    }

    enum CodingKeys: String, CodingKey { case id, text, kind, short, low, high, source, muted, cadence, requires }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try c.decodeIfPresent(CareQuestionKind.self, forKey: .kind) ?? .mood
        short = try c.decodeIfPresent(String.self, forKey: .short)
        low = try c.decodeIfPresent(String.self, forKey: .low)
        high = try c.decodeIfPresent(String.self, forKey: .high)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "custom"
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        cadence = try c.decodeIfPresent(String.self, forKey: .cadence) ?? "Daily"
        requires = try c.decodeIfPresent(String.self, forKey: .requires)
    }

    /// The wire shape when the owner saves their own questions.
    public var payload: [String: Any] {
        var out: [String: Any] = ["id": id, "text": text, "kind": kind == .unknown ? "yesno" : kind.rawValue]
        if let short { out["short"] = short }
        if let low { out["low"] = low }
        if let high { out["high"] = high }
        return out
    }
}

/// One yes/no on the care questionnaire the owner fills in about the parent.
/// The server owns the list; the widget only shows it.
public struct CareProfileField: Decodable, Equatable, Identifiable, Sendable {
    public var key: String
    public var question: String
    public var hint: String

    public var id: String { key }

    public init(key: String, question: String, hint: String = "") {
        self.key = key
        self.question = question
        self.hint = hint
    }

    enum CodingKeys: String, CodingKey { case key, question, hint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? key
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
    }
}

/// A family member on someone else's check-in. One child sets the arrangement
/// up and the rest join it, so the parent is asked once rather than once per
/// child. Two ways in: they ASK (the parent decides) or the owner INVITES them
/// (they decide, and the parent is told who joined and can remove anyone).
public struct CareWatcher: Decodable, Equatable, Identifiable, Sendable {
    public var userId: String
    public var name: String
    /// "invited" (waiting on someone's yes) or "active".
    public var status: String
    /// "self" when they asked; the owner's id when the owner invited them.
    public var invitedBy: String?
    public var invitedAt: Date?
    public var acceptedAt: Date?

    public var id: String { userId }
    public var isPending: Bool { status == "invited" }
    /// The owner sent this one an invitation (so THEY answer it, not the parent).
    public var isInvitedByOwner: Bool { !(invitedBy == nil || invitedBy == "self") }

    public init(userId: String, name: String, status: String, invitedBy: String? = nil, invitedAt: Date? = nil, acceptedAt: Date? = nil) {
        self.userId = userId
        self.name = name
        self.status = status
        self.invitedBy = invitedBy
        self.invitedAt = invitedAt
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
    /// The owner's answers about the parent (nil = questionnaire not done yet).
    public var profile: [String: Bool]?
    /// The questionnaire, as the server defines it.
    public var profileFields: [CareProfileField]
    public var mutedQuestionIds: [String]
    /// Everything that can be asked, given the profile: bank plus the owner's own.
    public var rotation: [CareQuestion]
    /// The parent's app can answer more than the three mood buttons.
    public var parentCanAnswerRich: Bool
    /// "HH:mm" in the parent's zone.
    public var times: [String]
    public var timezone: String?
    public var createdAt: Date?
    /// When the invitation push last went out (the first time = createdAt).
    public var lastInvitedAt: Date?
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
    /// Invited by the owner, or asking to join, and not yet in.
    public var isPendingWatcher: Bool { role == "pending_watcher" }
    /// Family waiting on a yes — the parent's (they asked) or their own (invited).
    public var pendingWatchers: [CareWatcher] { watchers.filter(\.isPending) }
    /// Requests the PARENT still has to answer.
    public var requestsForParent: [CareWatcher] { pendingWatchers.filter { !$0.isInvitedByOwner } }
    /// This viewer's own row on the plan, if they are on it.
    public func watcherEntry(for userId: String) -> CareWatcher? { watchers.first { $0.userId == userId } }
    public var activeWatchers: [CareWatcher] { watchers.filter { $0.status == "active" } }
    public var isInvited: Bool { status == "invited" }
    public var isActive: Bool { status == "active" }
    public var isPaused: Bool { status == "paused" }
    /// The other person, from the viewer's side.
    public var otherName: String { isOwner ? parentName : ownerName }
    public var hasProfile: Bool { profile != nil }
    /// The questions that will actually go out (not muted).
    public var activeRotation: [CareQuestion] { rotation.filter { !$0.muted } }

    public init(planId: String, role: String, ownerId: String, ownerName: String, parentId: String, parentName: String,
                status: String, questions: [CareQuestion] = [], usesDefaultQuestions: Bool = true, defaultQuestions: [String] = [],
                profile: [String: Bool]? = nil, profileFields: [CareProfileField] = [], mutedQuestionIds: [String] = [],
                rotation: [CareQuestion] = [], parentCanAnswerRich: Bool = false,
                times: [String] = ["08:30", "13:00", "19:00"], timezone: String? = nil, createdAt: Date? = nil, lastInvitedAt: Date? = nil,
                acceptedAt: Date? = nil, lastAskedAt: Date? = nil, lastAnsweredAt: Date? = nil, openAsk: CareAsk? = nil,
                lastAnswer: CareAsk? = nil, watchers: [CareWatcher] = []) {
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
        self.profile = profile
        self.profileFields = profileFields
        self.mutedQuestionIds = mutedQuestionIds
        self.rotation = rotation
        self.parentCanAnswerRich = parentCanAnswerRich
        self.times = times
        self.timezone = timezone
        self.createdAt = createdAt
        self.lastInvitedAt = lastInvitedAt ?? createdAt
        self.acceptedAt = acceptedAt
        self.lastAskedAt = lastAskedAt
        self.lastAnsweredAt = lastAnsweredAt
        self.openAsk = openAsk
        self.lastAnswer = lastAnswer
        self.watchers = watchers
    }

    enum CodingKeys: String, CodingKey {
        case planId, role, ownerId, ownerName, parentId, parentName, status, questions
        case usesDefaultQuestions, defaultQuestions, times, timezone, createdAt, lastInvitedAt, acceptedAt
        case lastAskedAt, lastAnsweredAt, openAsk, lastAnswer, watchers
        case profile, profileFields, mutedQuestionIds, rotation, parentCanAnswerRich
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
        profile = try c.decodeIfPresent([String: Bool].self, forKey: .profile)
        profileFields = try c.decodeIfPresent([CareProfileField].self, forKey: .profileFields) ?? []
        mutedQuestionIds = try c.decodeIfPresent([String].self, forKey: .mutedQuestionIds) ?? []
        rotation = try c.decodeIfPresent([CareQuestion].self, forKey: .rotation) ?? []
        parentCanAnswerRich = try c.decodeIfPresent(Bool.self, forKey: .parentCanAnswerRich) ?? false
        times = try c.decodeIfPresent([String].self, forKey: .times) ?? ["08:30", "13:00", "19:00"]
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        lastInvitedAt = try c.decodeIfPresent(Date.self, forKey: .lastInvitedAt) ?? createdAt
        acceptedAt = try c.decodeIfPresent(Date.self, forKey: .acceptedAt)
        lastAskedAt = try c.decodeIfPresent(Date.self, forKey: .lastAskedAt)
        lastAnsweredAt = try c.decodeIfPresent(Date.self, forKey: .lastAnsweredAt)
        openAsk = try c.decodeIfPresent(CareAsk.self, forKey: .openAsk)
        lastAnswer = try c.decodeIfPresent(CareAsk.self, forKey: .lastAnswer)
        watchers = try c.decodeIfPresent([CareWatcher].self, forKey: .watchers) ?? []
    }
}

/// Every side of the widget's world in one read.
public struct CarePlans: Decodable, Equatable, Sendable {
    public var asOwner: [CarePlan]
    public var asParent: [CarePlan]
    /// Plans someone else set up that this person was let in on.
    public var asWatcher: [CarePlan]
    /// Plans this person was invited to, or asked to join, and is not yet on.
    /// The arrangement only — the server sends no answers for these.
    public var asPending: [CarePlan]

    public init(asOwner: [CarePlan] = [], asParent: [CarePlan] = [], asWatcher: [CarePlan] = [], asPending: [CarePlan] = []) {
        self.asOwner = asOwner
        self.asParent = asParent
        self.asWatcher = asWatcher
        self.asPending = asPending
    }

    enum CodingKeys: String, CodingKey { case asOwner, asParent, asWatcher, asPending }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOwner = try c.decodeIfPresent([CarePlan].self, forKey: .asOwner) ?? []
        asParent = try c.decodeIfPresent([CarePlan].self, forKey: .asParent) ?? []
        asWatcher = try c.decodeIfPresent([CarePlan].self, forKey: .asWatcher) ?? []
        asPending = try c.decodeIfPresent([CarePlan].self, forKey: .asPending) ?? []
    }

    public var isEmpty: Bool { asOwner.isEmpty && asParent.isEmpty && asWatcher.isEmpty && asPending.isEmpty }
    /// Everything this person follows, however they came to it.
    public var following: [CarePlan] { asOwner + asWatcher }
    /// Invitations waiting on this person, then open questions for them.
    public var invitations: [CarePlan] { asParent.filter(\.isInvited) }
    /// "Take part in checking on Mom" — invitations from an owner that THIS
    /// person answers.
    public func familyInvitations(for userId: String) -> [CarePlan] {
        asPending.filter { $0.watcherEntry(for: userId)?.isInvitedByOwner == true }
    }
    /// Requests this person made that the parent has not answered yet.
    public func waitingOnParent(for userId: String) -> [CarePlan] {
        asPending.filter { $0.watcherEntry(for: userId).map { !$0.isInvitedByOwner } == true }
    }
    public var openAsks: [(plan: CarePlan, ask: CareAsk)] {
        asParent.compactMap { plan in plan.openAsk.map { (plan, $0) } }
    }
}

public enum CareCopy {
    public static let defaultTimes = ["08:30", "13:00", "19:00"]

    /// The glyph next to an answer in the history.
    public static func answerSymbol(_ ask: CareAsk) -> String {
        if ask.isMissed { return "moon.zzz" }
        guard ask.isAnswered else { return "clock" }
        if ask.alert { return "exclamationmark.triangle.fill" }
        switch ask.kind {
        case .mood, .unknown: return ask.answer?.symbolName ?? "hand.raised.fill"
        case .done, .yesno: return ask.answerValue == "yes" ? "checkmark.circle.fill" : (ask.answerValue == "not_yet" ? "clock.badge.questionmark" : "xmark.circle")
        case .scale: return "slider.horizontal.3"
        case .text: return "text.bubble.fill"
        }
    }

    /// One 0–10 question's recent readings: the last value and a 7-day average.
    public struct ScaleTrend: Equatable, Sendable {
        public var short: String
        public var latest: Int
        public var latestAt: Date
        public var average: Double
        public var count: Int
        public var lowLabel: String
        public var highLabel: String
        public var alerts: Int
        public var averageText: String { String(format: "%.1f", average) }
    }

    /// Trends per scale question over the last `days` days, most recent first,
    /// from a history newest-first. Pure, so the "This week" block is tested.
    public static func scaleTrends(_ history: [CareAsk], now: Date = Date(), days: Int = 7) -> [ScaleTrend] {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        var byShort: [String: [CareAsk]] = [:]
        var order: [String] = []
        for ask in history where ask.kind == .scale && ask.isAnswered {
            guard let at = ask.answeredAt, at >= since, ask.answerScore != nil else { continue }
            let key = ask.short ?? ask.questionText
            if byShort[key] == nil { order.append(key) }
            byShort[key, default: []].append(ask)
        }
        return order.compactMap { key in
            guard let asks = byShort[key], let first = asks.first, let latest = first.answerScore, let at = first.answeredAt else { return nil }
            let scores = asks.compactMap(\.answerScore)
            return ScaleTrend(short: key, latest: latest, latestAt: at, average: Double(scores.reduce(0, +)) / Double(scores.count),
                              count: scores.count, lowLabel: first.low ?? "0", highLabel: first.high ?? "10", alerts: asks.filter(\.alert).count)
        }
    }

    /// The answers the family was told to notice, most recent first, within `days`.
    public static func recentAlerts(_ history: [CareAsk], now: Date = Date(), days: Int = 7) -> [CareAsk] {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        return history.filter { $0.alert && ($0.answeredAt ?? .distantPast) >= since }
    }

    /// "5 of 6 answered this week", counting asks that reached their phone.
    public static func answerRate(_ history: [CareAsk], now: Date = Date(), days: Int = 7) -> (answered: Int, asked: Int) {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        let inWindow = history.filter { $0.askedAt >= since && $0.pushDelivered && !$0.isOpen }
        return (inWindow.filter(\.isAnswered).count, inWindow.count)
    }

    /// The profile as a line: "Lives alone · takes medication · PT".
    public static func profileSummary(_ plan: CarePlan) -> String {
        guard let profile = plan.profile else { return "" }
        let words: [(String, String)] = [
            ("livesAlone", "lives alone"), ("takesMeds", "takes medication"), ("hasPT", "in physical therapy"),
            ("chronicPain", "ongoing pain"), ("sleepConcern", "sleep is a worry"), ("fallRisk", "fall risk"),
            ("checksBloodSugar", "checks blood sugar"), ("checksBloodPressure", "checks blood pressure"), ("needsRides", "needs rides")
        ]
        let on = words.filter { profile[$0.0] == true }.map(\.1)
        return on.isEmpty ? "Nothing special noted — the everyday questions only." : on.joined(separator: " · ").prefix(1).uppercased() + on.joined(separator: " · ").dropFirst()
    }

    /// What the owner is told when the parent's app can't take the new kinds yet.
    public static func needsUpdateLine(_ plan: CarePlan) -> String? {
        guard plan.isActive || plan.isPaused, !plan.parentCanAnswerRich else { return nil }
        return "\(plan.parentName)'s Circles app needs an update before the yes/no and 0–10 questions can reach their Lock Screen. Until then they get the simple \"how are you?\" questions."
    }

    /// The list to send when the owner adds a question. On a plan still on
    /// the rotating defaults, the defaults come along as the owner's own
    /// (each now removable) and the new one joins the rotation — adding a
    /// question must never make the other questions disappear.
    public static func questionsAfterAdding(_ text: String, to plan: CarePlan) -> [String] {
        let base = plan.usesDefaultQuestions ? plan.defaultQuestions : plan.questions.map(\.text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !base.contains(trimmed) else { return base }
        return base + [trimmed]
    }
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
    /// Under "Waiting for Mom to accept": when the invitation last went out,
    /// so a child knows whether a nudge is overdue or just sent.
    public static func invitedLine(_ plan: CarePlan, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let at = plan.lastInvitedAt else { return "They'll see the invitation in their Circles app. Nothing is asked until they say yes." }
        return "Invitation sent \(relative(at, now: now, calendar: calendar)). They'll see it in their Circles app; nothing is asked until they say yes."
    }

    /// What the child is told after "Send the invitation again".
    public static func resendResult(_ plan: CarePlan, delivered: Bool) -> String {
        delivered
            ? "Sent to \(plan.parentName) again."
            : "\(plan.parentName)'s phone isn't getting notifications right now. The invitation is still waiting in their How Are You? widget."
    }

    /// One line per family member on the plan's family list.
    public static func watcherLine(_ watcher: CareWatcher, parentName: String) -> String {
        if !watcher.isPending { return "Sees the answers" }
        return watcher.isInvitedByOwner ? "Invited · waiting on them" : "Asked to join · waiting on \(parentName)"
    }

    /// After the owner sends (or re-sends) a family invitation.
    public static func familyInviteResult(_ name: String, parentName: String, delivered: Bool) -> String {
        delivered
            ? "\(name) has the invitation. They decide; \(parentName) will be told once they join."
            : "\(name)'s phone didn't get the invitation right now. It's waiting in their widget, and you can send it again in a few minutes."
    }

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

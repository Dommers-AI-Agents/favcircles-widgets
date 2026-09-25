import Testing
import Foundation
@testable import FavWidgetsCore

// MARK: - Siblings

@Suite("Care watchers")
struct CareWatcherTests {
    /// A server that predates watchers must still decode — a widget that
    /// refuses to parse is a blank screen, and this one is how a family finds
    /// out a parent has gone quiet.
    @Test func aPlanWithoutWatchersStillDecodes() throws {
        let json = """
        {"planId":"p1","role":"owner","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom",
         "status":"active","questions":[],"usesDefaultQuestions":true,"defaultQuestions":[],
         "times":["08:30"],"timezone":"America/New_York"}
        """
        let plan = try JSONDecoder().decode(CarePlan.self, from: Data(json.utf8))
        #expect(plan.watchers.isEmpty)
        #expect(plan.activeWatchers.isEmpty)
        #expect(plan.isOwner)
    }

    @Test func rolesSplitReadersFromTheOneWhoSetItUp() throws {
        let json = """
        {"planId":"p1","role":"watcher","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom",
         "status":"active","watchers":[
           {"userId":"c2","name":"Kate","status":"active"},
           {"userId":"c3","name":"Sam","status":"invited"}]}
        """
        let plan = try JSONDecoder().decode(CarePlan.self, from: Data(json.utf8))
        #expect(plan.isWatcher)
        #expect(!plan.isOwner)
        #expect(plan.activeWatchers.map(\.name) == ["Kate"])
        #expect(plan.pendingWatchers.map(\.name) == ["Sam"])
    }

    @Test func watchedPlansListAlongsideOwnedOnes() throws {
        let json = """
        {"asOwner":[{"planId":"p1","role":"owner","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom","status":"active"}],
         "asParent":[],
         "asWatcher":[{"planId":"p2","role":"watcher","ownerId":"c2","ownerName":"Kate","parentId":"d1","parentName":"Dad","status":"active"}]}
        """
        let plans = try JSONDecoder().decode(CarePlans.self, from: Data(json.utf8))
        #expect(plans.following.map(\.planId) == ["p1", "p2"])
        #expect(!plans.isEmpty)

        // An older server sends neither key.
        let old = try JSONDecoder().decode(CarePlans.self, from: Data(#"{"asOwner":[],"asParent":[]}"#.utf8))
        #expect(old.asWatcher.isEmpty)
        #expect(old.asPending.isEmpty)
        #expect(old.isEmpty)
    }

    /// Two ways onto a check-in: an invitation from the owner (mine to answer)
    /// and a request of my own (the parent's). Both sit in `asPending` until
    /// someone says yes; the widget must tell them apart.
    @Test func anInvitationIsMineToAnswerAndARequestIsTheParents() throws {
        let json = """
        {"asOwner":[],"asParent":[],"asWatcher":[],
         "asPending":[
           {"planId":"p1","role":"pending_watcher","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom","status":"active",
            "watchers":[{"userId":"c2","name":"Kate","status":"invited","invitedBy":"c1","invitedAt":"2026-09-25T12:00:00.000Z"}]},
           {"planId":"p2","role":"pending_watcher","ownerId":"c3","ownerName":"Sam","parentId":"d1","parentName":"Dad","status":"active",
            "watchers":[{"userId":"c2","name":"Kate","status":"invited","invitedBy":"self"}]}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plans = try decoder.decode(CarePlans.self, from: Data(json.utf8))
        #expect(plans.asPending.count == 2)
        #expect(!plans.isEmpty)
        #expect(plans.familyInvitations(for: "c2").map(\.planId) == ["p1"])
        #expect(plans.waitingOnParent(for: "c2").map(\.planId) == ["p2"])
        // Nothing of it is "followed" — no answers come with a pending plan.
        #expect(plans.following.isEmpty)
        let invite = try #require(plans.asPending[0].watcherEntry(for: "c2"))
        #expect(invite.isInvitedByOwner)
        #expect(invite.invitedAt != nil)
        #expect(CareCopy.watcherLine(invite, parentName: "Mom") == "Invited · waiting on them")
        let request = try #require(plans.asPending[1].watcherEntry(for: "c2"))
        #expect(!request.isInvitedByOwner)
        #expect(CareCopy.watcherLine(request, parentName: "Dad") == "Asked to join · waiting on Dad")
        #expect(CareCopy.watcherLine(CareWatcher(userId: "x", name: "Sam", status: "active"), parentName: "Dad") == "Sees the answers")
    }

    /// The parent's approval card must not show an invitation the owner sent —
    /// that one is the invited person's to answer.
    @Test func theParentOnlyApprovesRequestsNotInvitations() throws {
        let plan = CarePlan(planId: "p", role: "parent", ownerId: "c1", ownerName: "Wes", parentId: "m1", parentName: "Mom", status: "active",
                            watchers: [CareWatcher(userId: "c2", name: "Kate", status: "invited", invitedBy: "c1"),
                                       CareWatcher(userId: "c3", name: "Sam", status: "invited", invitedBy: "self"),
                                       CareWatcher(userId: "c4", name: "Ann", status: "active", invitedBy: "c1")])
        #expect(plan.requestsForParent.map(\.name) == ["Sam"])
        #expect(plan.pendingWatchers.map(\.name) == ["Kate", "Sam"])
        #expect(plan.activeWatchers.map(\.name) == ["Ann"])
    }
}


// MARK: - Questions

@Suite("Care questions")
struct CareQuestionTests {
    private func plan(questions: [String], defaults: [String] = ["How are you feeling today?", "Did you sleep well?"]) throws -> CarePlan {
        let object: [String: Any] = [
            "planId": "p", "role": "owner", "ownerId": "o", "ownerName": "Wes", "parentId": "s", "parentName": "Sal",
            "status": "active", "times": ["08:30"], "watchers": [],
            "questions": questions.enumerated().map { ["id": "q\($0.offset)", "text": $0.element] },
            "usesDefaultQuestions": questions.isEmpty, "defaultQuestions": defaults
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(CarePlan.self, from: data)
    }

    /// Wes added one question for Sal and the eight defaults vanished —
    /// the first custom question used to REPLACE the rotation.
    @Test func theFirstOwnQuestionJoinsTheDefaultsInsteadOfReplacingThem() throws {
        let p = try plan(questions: [])
        #expect(CareCopy.questionsAfterAdding("Did you swim today?", to: p)
                == ["How are you feeling today?", "Did you sleep well?", "Did you swim today?"])
    }

    @Test func laterQuestionsAppendToTheOwnList() throws {
        let p = try plan(questions: ["Did you swim today?"])
        #expect(CareCopy.questionsAfterAdding(" Any pain? ", to: p) == ["Did you swim today?", "Any pain?"])
    }

    @Test func blankOrDuplicateChangesNothing() throws {
        let p = try plan(questions: ["Did you swim today?"])
        #expect(CareCopy.questionsAfterAdding("   ", to: p) == ["Did you swim today?"])
        #expect(CareCopy.questionsAfterAdding("Did you swim today?", to: p) == ["Did you swim today?"])
    }
}

// MARK: - Question kinds, the care profile and this week's trends

@Suite("Care question kinds")
struct CareQuestionKindTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// A server that predates kinds sent bare mood asks; they must still be mood.
    @Test func aLegacyAskIsAMoodQuestion() throws {
        let json = """
        {"askId":"a1","planId":"p1","questionText":"How are you feeling today?","slot":"08:30","dateKey":"2026-09-19",
         "askedAt":"2026-09-19T12:35:00Z","status":"answered","answer":"okay","answerText":"Okay","note":""}
        """
        let ask = try decoder.decode(CareAsk.self, from: Data(json.utf8))
        #expect(ask.kind == .mood)
        #expect(ask.answer == .okay)
        #expect(ask.answerValue == "okay")
        #expect(ask.alert == false)
        #expect(CareCopy.answerSymbol(ask) == "hand.raised.fill")
    }

    @Test func aScaleAskCarriesItsLabelsScoreAndAlert() throws {
        let json = """
        {"askId":"a2","planId":"p1","questionText":"How much pain are you in today?","kind":"scale","short":"Pain",
         "low":"No pain","high":"Worst pain","slot":"13:00","dateKey":"2026-09-21","askedAt":"2026-09-21T17:05:00Z",
         "status":"answered","answer":null,"answerValue":"8","answerScore":8,"answerText":"Pain 8/10","alert":true,"note":"my hip"}
        """
        let ask = try decoder.decode(CareAsk.self, from: Data(json.utf8))
        #expect(ask.kind == .scale)
        #expect(ask.answer == nil)
        #expect(ask.answerScore == 8)
        #expect(ask.answerText == "Pain 8/10")
        #expect(ask.alert)
        #expect(CareCopy.answerSymbol(ask) == "exclamationmark.triangle.fill")
    }

    @Test func anUnknownKindStillDecodesAndAnswersWithMoodButtons() throws {
        let json = """
        {"askId":"a3","planId":"p1","questionText":"Something new?","kind":"emoji_grid","askedAt":"2026-09-21T17:05:00Z","status":"open"}
        """
        let ask = try decoder.decode(CareAsk.self, from: Data(json.utf8))
        #expect(ask.kind == .unknown)
        #expect(ask.kind.choices.map(\.key) == ["great", "okay", "not_great"])
    }

    @Test func choiceButtonsPerKind() {
        #expect(CareQuestionKind.done.choices.map(\.label) == ["Yes", "Not yet", "No"])
        #expect(CareQuestionKind.yesno.choices.map(\.key) == ["yes", "no"])
        #expect(CareQuestionKind.scale.choices.isEmpty)
        #expect(CareQuestionKind.text.choices.isEmpty)
        #expect(CareQuestionKind.pickable.first == .yesno) // a typed question defaults to a plain yes/no
    }

    /// A choice goes as `answer`, a number or words as `value` — what the server's answerAsk expects.
    @Test func answerPayloadShapes() {
        #expect(CareAnswerPayload.choice("not_yet").body(note: "") as NSDictionary == ["answer": "not_yet", "note": ""] as NSDictionary)
        #expect(CareAnswerPayload.scale(7).body(note: "hip") as NSDictionary == ["value": 7, "note": "hip"] as NSDictionary)
        #expect(CareAnswerPayload.text("eye doctor Thursday").body(note: "") as NSDictionary == ["value": "eye doctor Thursday", "note": ""] as NSDictionary)
        #expect(CareAnswerPayload.text("x").trackingValue == "text")
        #expect(CareAnswerPayload.scale(3).trackingValue == "3")
    }

    @Test func aPlanDecodesItsProfileRotationAndCapability() throws {
        let json = """
        {"planId":"p1","role":"owner","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom","status":"active",
         "profile":{"livesAlone":true,"takesMeds":true,"hasPT":false},
         "profileFields":[{"key":"livesAlone","question":"Do they live alone?","hint":"..."},{"key":"takesMeds","question":"Do they take medication every day?"}],
         "mutedQuestionIds":["water"],
         "rotation":[
           {"id":"mood_morning","text":"How are you feeling today?","kind":"mood","source":"bank","muted":false,"cadence":"Daily"},
           {"id":"water","text":"Are you drinking enough water today?","kind":"done","source":"bank","muted":true,"cadence":"Every 2 days"},
           {"id":"meds_filled","text":"Are all your medications filled?","kind":"yesno","source":"bank","muted":false,"cadence":"Weekly · Mondays","requires":"takesMeds"},
           {"id":"q9","text":"Did the nurse come?","kind":"yesno","source":"custom","muted":false,"cadence":"Daily"}],
         "parentCanAnswerRich":false}
        """
        let plan = try decoder.decode(CarePlan.self, from: Data(json.utf8))
        #expect(plan.hasProfile)
        #expect(plan.profile?["livesAlone"] == true)
        #expect(plan.profileFields.count == 2)
        #expect(plan.profileFields[1].hint == "")
        #expect(plan.rotation.count == 4)
        #expect(plan.activeRotation.count == 3)
        #expect(plan.rotation[2].requires == "takesMeds")
        #expect(plan.rotation[3].isCustom)
        #expect(CareCopy.profileSummary(plan) == "Lives alone · takes medication")
        #expect(CareCopy.needsUpdateLine(plan)?.hasPrefix("Mom's Circles app needs an update") == true)
        var rich = plan
        rich.parentCanAnswerRich = true
        #expect(CareCopy.needsUpdateLine(rich) == nil)
        // The wire shape for the owner's own question keeps its kind and drops nothing it needs.
        let payload = plan.rotation[3].payload
        #expect(payload["kind"] as? String == "yesno")
        #expect(payload["text"] as? String == "Did the nurse come?")
    }

    @Test func aPlanWithoutAProfileDecodesAndAsksForOne() throws {
        let json = """
        {"planId":"p1","role":"owner","ownerId":"c1","ownerName":"Wes","parentId":"m1","parentName":"Mom","status":"invited"}
        """
        let plan = try decoder.decode(CarePlan.self, from: Data(json.utf8))
        #expect(!plan.hasProfile)
        #expect(plan.rotation.isEmpty)
        #expect(CareCopy.needsUpdateLine(plan) == nil) // not active yet: nothing to warn about
        var none = plan
        none.profile = [:]
        #expect(CareCopy.profileSummary(none).hasPrefix("Nothing special noted"))
    }

    @Test func thisWeeksTrendsAlertsAndAnswerRate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func ask(_ id: String, kind: CareQuestionKind, short: String? = nil, daysAgo: Double, score: Int? = nil, status: String = "answered", alert: Bool = false, delivered: Bool = true) -> CareAsk {
            let at = now.addingTimeInterval(-daysAgo * 86400)
            return CareAsk(askId: id, planId: "p", questionText: short ?? id, kind: kind, short: short, low: "None", high: "Worst",
                           askedAt: at, status: status, answerScore: score, answerText: score.map { "\(short ?? "") \($0)/10" }, alert: alert,
                           answeredAt: status == "answered" ? at : nil, pushDelivered: delivered)
        }
        let history = [
            ask("a1", kind: .scale, short: "Pain", daysAgo: 0.5, score: 8, alert: true),
            ask("a2", kind: .done, daysAgo: 1),
            ask("a3", kind: .scale, short: "Pain", daysAgo: 2, score: 4),
            ask("a4", kind: .scale, short: "Sleep", daysAgo: 3, score: 6),
            ask("a5", kind: .mood, daysAgo: 4, status: "missed"),
            ask("a6", kind: .mood, daysAgo: 5, status: "missed", delivered: false),
            ask("a7", kind: .scale, short: "Pain", daysAgo: 9, score: 9, alert: true) // last week: out of the window
        ]
        let trends = CareCopy.scaleTrends(history, now: now)
        #expect(trends.map(\.short) == ["Pain", "Sleep"])
        #expect(trends[0].latest == 8)
        #expect(trends[0].count == 2)
        #expect(trends[0].averageText == "6.0")
        #expect(trends[0].alerts == 1)
        #expect(trends[1].count == 1)
        #expect(CareCopy.recentAlerts(history, now: now).map(\.askId) == ["a1"])
        let rate = CareCopy.answerRate(history, now: now)
        #expect(rate.answered == 4)
        #expect(rate.asked == 5) // the undelivered one doesn't count against them
    }
}

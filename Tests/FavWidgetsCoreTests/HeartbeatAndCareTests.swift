import Testing
import Foundation
@testable import FavWidgetsCore

struct HeartbeatTests {
    /// A pulse-like signal: a slow drift plus a 1.2 Hz beat plus noise.
    private static func feed(_ estimator: inout HeartRateEstimator, bpm: Double, seconds: Double, rate: Double = 30, noise: Double = 0.3, seed: UInt32 = 5) {
        var rng = NoiseRNG(seed: seed)
        let hz = bpm / 60
        let frames = Int(seconds * rate)
        for i in 0..<frames {
            let t = Double(i) / rate
            let drift = 150 + 20 * t / seconds
            let beat = 4 * sin(2 * Double.pi * hz * t) + 1.2 * sin(4 * Double.pi * hz * t)
            estimator.add(value: drift + beat + Double(rng.next()) * noise, at: t)
        }
    }

    @Test(arguments: [52.0, 72.0, 95.0, 140.0])
    func estimatesTheRateWithinThreeBPM(bpm: Double) {
        var estimator = HeartRateEstimator(sampleRate: 30, windowSeconds: 8)
        Self.feed(&estimator, bpm: bpm, seconds: 12)
        let estimate = estimator.estimate()
        #expect(estimate != nil)
        #expect(abs(Double(estimate!.bpm) - bpm) <= 3, "got \(estimate!.bpm) for \(bpm)")
        #expect(estimate!.confidence > 0.5)
    }

    @Test func needsAFewSecondsBeforeItAnswers() {
        var estimator = HeartRateEstimator(sampleRate: 30, windowSeconds: 8)
        Self.feed(&estimator, bpm: 70, seconds: 3)
        #expect(!estimator.isReady)
        #expect(estimator.estimate() == nil)
        Self.feed(&estimator, bpm: 70, seconds: 7)
        #expect(estimator.isReady)
    }

    @Test func pureNoiseHasLowConfidence() {
        var estimator = HeartRateEstimator(sampleRate: 30, windowSeconds: 8)
        var rng = NoiseRNG(seed: 9)
        for i in 0..<300 { estimator.add(value: 150 + Double(rng.next()) * 5, at: Double(i) / 30) }
        let estimate = estimator.estimate()
        #expect((estimate?.confidence ?? 0) < 0.5)
    }

    @Test func fingerDetection() {
        #expect(HeartRateEstimator.isFingerCovering(meanRed: 180, meanGreen: 40, meanBlue: 30))
        #expect(!HeartRateEstimator.isFingerCovering(meanRed: 120, meanGreen: 110, meanBlue: 100)) // a room
        #expect(!HeartRateEstimator.isFingerCovering(meanRed: 40, meanGreen: 10, meanBlue: 10)) // too dark
    }

    @Test func monthStatsAndMerge() {
        let a = HeartReading(id: "a", at: Date(timeIntervalSince1970: 1), bpm: 60, source: .camera)
        let b = HeartReading(id: "b", at: Date(timeIntervalSince1970: 2), bpm: 80, source: .strap)
        let merged = HeartbeatMonth.merge(local: HeartbeatMonth(readings: [a]), remote: HeartbeatMonth(readings: [b, a]))
        #expect(merged.readings.map(\.id) == ["a", "b"])
        #expect(merged.stats! == (60, 70, 80))
        #expect(merged.latest?.id == "b")
        #expect(HeartbeatCopy.monthLine(merged) == "2 readings · low 60 · average 70 · high 80")
        #expect(HeartbeatCopy.band(bpm: 72) == "Typical resting range")
        #expect(HeartbeatCopy.band(bpm: 55) == "Athlete range")
        #expect(HeartbeatCopy.band(bpm: 110) == "Elevated")
    }

    @Test func unknownSourceDecodesSafely() throws {
        let json = #"{"readings":[{"id":"x","at":"2026-09-19T10:00:00Z","bpm":70,"source":"implant","confidence":1}]}"#
        let month = try WidgetJSON.decode(HeartbeatMonth.self, from: Data(json.utf8))
        #expect(month.readings.first?.source == .unknown)
    }
}

struct CareModelTests {
    static let plansJSON = """
    {"success":true,
     "asOwner":[{"planId":"me_mom","role":"owner","ownerId":"me","ownerName":"Wes","parentId":"mom","parentName":"Mom","status":"active",
       "questions":[],"usesDefaultQuestions":true,"defaultQuestions":["How are you feeling today?"],"times":["08:30","13:00","19:00"],"timezone":"America/New_York",
       "createdAt":"2026-09-18T12:00:00.000Z","acceptedAt":"2026-09-18T13:00:00.000Z","lastAskedAt":"2026-09-19T12:30:00.000Z","lastAnsweredAt":null,
       "openAsk":{"askId":"a1","planId":"me_mom","questionText":"Did you sleep well?","slot":"08:30","dateKey":"2026-09-19","askedAt":"2026-09-19T12:30:00.000Z","dueBy":"2026-09-19T15:30:00.000Z","status":"open","answer":null,"answerText":null,"note":"","answeredAt":null,"pushDelivered":true},
       "lastAnswer":null,"answers":{"great":"Doing great 👍","okay":"Okay","not_great":"Not so good"}}],
     "asParent":[{"planId":"dad_me","role":"parent","ownerId":"dad","ownerName":"Dad","parentId":"me","parentName":"Wes","status":"invited",
       "questions":[],"usesDefaultQuestions":true,"defaultQuestions":[],"times":["09:00"],"timezone":null,"createdAt":"2026-09-19T00:00:00Z","acceptedAt":null,"lastAskedAt":null,"lastAnsweredAt":null,"openAsk":null,"lastAnswer":null,"answers":{}}]}
    """

    @Test func decodesBothRoles() throws {
        let plans = try WidgetJSON.decode(CarePlans.self, from: Data(Self.plansJSON.utf8))
        #expect(plans.asOwner.first?.isOwner == true)
        #expect(plans.asOwner.first?.openAsk?.questionText == "Did you sleep well?")
        #expect(plans.invitations.map(\.ownerName) == ["Dad"])
        #expect(plans.openAsks.isEmpty) // the open ask belongs to Mom, not to this viewer
    }

    @Test func unknownAnswerValueDecodesAsNil() throws {
        let json = #"{"asks":[{"askId":"a","planId":"p","questionText":"Q","slot":"08:30","dateKey":"d","askedAt":"2026-09-19T12:30:00Z","status":"answered","answer":"ecstatic","answerText":"Ecstatic","note":"","answeredAt":"2026-09-19T12:40:00Z","pushDelivered":true}]}"#
        struct Asks: Decodable { let asks: [CareAsk] }
        let asks = try WidgetJSON.decode(Asks.self, from: Data(json.utf8)).asks
        #expect(asks.first?.answer == nil)
        #expect(asks.first?.answerText == "Ecstatic")
    }

    @Test func cardCopyLeadsWithWhatNeedsAnAnswer() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let plans = try WidgetJSON.decode(CarePlans.self, from: Data(Self.plansJSON.utf8))
        // An invitation outranks everything.
        #expect(CareCopy.cardSummary(plans, calendar: cal) == "Dad wants to check in on you")
        var noInvite = plans
        noInvite.asParent = []
        let before = Date(timeIntervalSince1970: 1_789_000_000 + 0) // any time before dueBy in 2026-09-19? use explicit
        _ = before
        let waiting = ISO8601DateFormatter().date(from: "2026-09-19T13:00:00Z")!
        #expect(CareCopy.cardSummary(noInvite, now: waiting, calendar: cal) == "Asked Mom at 8:30 AM · waiting")
        let overdue = ISO8601DateFormatter().date(from: "2026-09-19T16:00:00Z")!
        #expect(CareCopy.cardSummary(noInvite, now: overdue, calendar: cal) == "Mom hasn't answered since 8:30 AM")
        #expect(CareCopy.cardSummary(nil, calendar: cal) == "Check on Mom or Dad, a few times a day")
        #expect(CareCopy.timesLine(["08:30", "13:00", "19:00"], locale: Locale(identifier: "en_US")) == "8:30 AM, 1:00 PM and 7:00 PM")
        #expect(CareCopy.timeChoices.first == "06:00" && CareCopy.timeChoices.last == "22:30")
    }
}

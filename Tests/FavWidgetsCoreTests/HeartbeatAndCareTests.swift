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

    /// A fingertip signal as the camera really sees it: a sharp systolic
    /// upstroke and a dicrotic bump each beat, a little beat-to-beat wobble,
    /// a breathing / hand-movement swell, sensor noise, and dropped frames
    /// with their real timestamps. 20 s, the longest a measurement runs.
    private static func fingertip(bpm: Double, swellHz: Double, swellAmp: Double, pulseAmp: Double = 1.5,
                                  noise: Double = 0.5, dropRate: Double = 0, seed: UInt64) -> [(time: Double, red: Double)] {
        var state = seed
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        func beat(_ phase: Double) -> Double {
            let p = phase - floor(phase)
            return -(exp(-pow((p - 0.15) / 0.07, 2)) + 0.35 * exp(-pow((p - 0.45) / 0.08, 2)))
        }
        var samples: [(time: Double, red: Double)] = []
        var phase = 0.0
        var t = 0.0
        while t < 20 {
            phase += bpm / 60 * (1 + 0.03 * sin(2 * .pi * swellHz * t)) / 30
            t += 1.0 / 30
            if random() < dropRate { continue }
            samples.append((t, 200 + swellAmp * sin(2 * .pi * swellHz * t) + pulseAmp * beat(phase) + (random() - 0.5) * 2 * noise))
        }
        return samples
    }

    /// Runs the tracker the way CameraPulseMonitor does: stop once steady
    /// after 8 s, or at 20 s, and keep the result only if it has consensus.
    private static func measure(_ samples: [(time: Double, red: Double)]) -> Int? {
        var tracker = PulseTracker()
        guard let start = samples.first?.time else { return nil }
        for sample in samples {
            tracker.add(value: sample.red, at: sample.time)
            if sample.time - start >= 8 && tracker.isSteady { break }
        }
        return tracker.result
    }

    /// Wes 2026-09-28: a 135 bpm pulse read 50. Heavy breathing (or a hand
    /// moving with it) near 0.8 Hz swamped the old autocorrelation.
    @Test(arguments: [
        (135.0, 0.8, 3.0, 0.0),   // the reported case: fast, heavy breathing
        (135.0, 0.5, 4.0, 0.0),   // slower, deeper breaths
        (135.0, 0.4, 1.0, 0.25),  // a quarter of the frames dropped
        (170.0, 0.7, 3.0, 0.1),   // hard exercise
        (70.0, 0.25, 1.0, 0.05),  // resting
        (55.0, 0.25, 1.0, 0.05)   // an athlete resting
    ])
    func readsARealisticFingertip(bpm: Double, swellHz: Double, swellAmp: Double, dropRate: Double) {
        for seed in UInt64(1)...5 {
            let result = Self.measure(Self.fingertip(bpm: bpm, swellHz: swellHz, swellAmp: swellAmp, dropRate: dropRate, seed: seed))
            #expect(result != nil, "no reading for \(bpm), seed \(seed)")
            #expect(abs(Double(result ?? 0) - bpm) <= 3, "got \(result ?? 0) for \(bpm), seed \(seed)")
        }
    }

    @Test func medianAndConsensus() {
        #expect(HeartRateEstimator.median([]) == nil)
        #expect(HeartRateEstimator.median([50, 135, 136, 134]) == 135)
        #expect(HeartRateEstimator.median([70, 72, 150]) == 72)
        #expect(HeartRateEstimator.hasConsensus([135, 136, 134, 50, 137]))
        #expect(!HeartRateEstimator.hasConsensus([163, 120, 187, 90, 150, 60]))
        #expect(!HeartRateEstimator.hasConsensus([]))
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

    @Test func steadyOnceSixEstimatesAgree() {
        #expect(!HeartRateEstimator.isSteady([70, 71, 70, 72, 71]))               // not enough yet
        #expect(HeartRateEstimator.isSteady([90, 70, 71, 70, 72, 71, 70]))        // an old outlier doesn't count
        #expect(!HeartRateEstimator.isSteady([70, 71, 70, 72, 71, 78]))           // still moving
        #expect(HeartRateEstimator.isSteady([68, 71, 70, 72, 71, 73]))            // within ±3 of the mean
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

@Suite("Care invitation resend")
struct CareInviteResendTests {
    private let cal = Calendar(identifier: .gregorian)

    @Test func lastInvitedAtFallsBackToCreatedAtForOlderServers() throws {
        let json = """
        {"planId":"p1","role":"owner","ownerId":"c1","parentName":"Dad","status":"invited","createdAt":"2026-09-19T23:41:28.388Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(CarePlan.self, from: Data(json.utf8))
        #expect(plan.lastInvitedAt == plan.createdAt)
    }

    @Test func invitedLineSaysWhenItWentOut() {
        let sent = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = CarePlan(planId: "p1", role: "owner", ownerId: "c1", ownerName: "Wes", parentId: "d1", parentName: "Dad",
                            status: "invited", lastInvitedAt: sent)
        let line = CareCopy.invitedLine(plan, now: sent.addingTimeInterval(3 * 60), calendar: cal)
        #expect(line.hasPrefix("Invitation sent "))
        #expect(line.hasSuffix("nothing is asked until they say yes."))
        let bare = CarePlan(planId: "p1", role: "owner", ownerId: "c1", ownerName: "Wes", parentId: "d1", parentName: "Dad", status: "invited")
        #expect(CareCopy.invitedLine(bare, calendar: cal).hasPrefix("They'll see the invitation"))
    }

    @Test func resendResultTellsTheTruthAboutDelivery() {
        let plan = CarePlan(planId: "p1", role: "owner", ownerId: "c1", ownerName: "Wes", parentId: "d1", parentName: "Dad", status: "invited")
        #expect(CareCopy.resendResult(plan, delivered: true) == "Sent to Dad again.")
        #expect(CareCopy.resendResult(plan, delivered: false).hasPrefix("Dad's phone isn't getting notifications"))
        #expect(CareCopy.resendResult(plan, delivered: false, emailed: true).contains("so we emailed the invitation too"))
        #expect(CareCopy.resendResult(plan, delivered: true, emailed: true) == "Sent to Dad again, as a notification and an email.")
        #expect(CareCopy.familyInviteResult("Kate", parentName: "Dad", delivered: false, emailed: true).contains("emailed the invitation"))
    }
}

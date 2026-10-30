import Foundation
import FavWidgetsCore
#if os(iOS)
import CoreLocation
import UIKit
#endif

/// The run in progress. One per app, so a run keeps going while you leave
/// the widget, lock the phone (background location; the blue pill shows
/// it's on) or use the rest of the app. The lock-screen Live Activity can
/// pause, resume and finish it (`togglePause()` / `requestFinish()`).
@MainActor
public final class RunSession: NSObject, ObservableObject {
    public static let shared = RunSession()

    public enum Phase: Equatable { case idle, running, paused, finished }
    public enum Problem: Equatable { case locationDenied, locationOff }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var track: RunTrack?
    @Published public private(set) var now = Date()
    @Published public private(set) var problem: Problem?
    /// Set by the lock screen's Finish: the run page opens the summary.
    @Published public var finishRequested = false
    @Published public private(set) var waitingForGPS = false

    public var unit: RunUnit = .localeDefault
    /// Coach Mane yells after every mile/km (can be muted mid-run)
    @Published public var coachOn = false
    public var coachIntensity: MotivationIntensity = .savage
    private var coachedSplits = 0
    private weak var host: FavWidgetHost?
    private var context: WidgetContext?

    // Watching live (2026-10-06): the shared run's id once anyone's invited
    @Published public private(set) var liveRun: SharedRun?
    /// The newest cheer to pop up on the runner's screen
    @Published public var newCheer: SharedRun.Cheer?
    /// Who's following along right now ("Sal, Brit")
    @Published public private(set) var watcherNames: [String] = []
    /// Followers waiting for their "watch live" push. Kept and retried every
    /// 15 s until it goes through (2026-10-13: one lost reply on a weak
    /// signal used to drop everyone's invite silently).
    @Published public private(set) var followersWaiting: [RunFollower] = []
    /// Followers who've been told
    @Published public private(set) var followersTold: [RunFollower] = []
    /// The last try to reach the server failed (shown as "No signal")
    @Published public private(set) var liveNoSignal = false
    /// This run's id for the server, so a retry after a lost reply gets the
    /// same shared run instead of a second one
    private var clientKey = UUID().uuidString
    private var lastLiveAttempt = Date.distantPast
    private var attemptingLive = false
    private static let liveRetryInterval: TimeInterval = 15

    /// The run screen's line about who knows you're running
    public var followersStatus: String? {
        RunFollowersCopy.status(waiting: followersWaiting.map(\.name), told: followersTold.map(\.name), noSignal: liveNoSignal)
    }
    private var seenCheers = Set<String>()
    private var lastLiveSync = Date.distantPast
    private var lastSyncedSplits = 0
    private var syncing = false
    private var ticker: Timer?
    private var lastLivePush = Date.distantPast
    /// Saved to this phone every few seconds so the run survives the app
    /// closing (RunCheckpoint). Kept by the session: a host passed to
    /// `restoreIfNeeded` before any widget page exists must stay alive.
    private var lastCheckpoint = Date.distantPast
    private static let checkpointInterval: TimeInterval = 5
    private var restoreHost: FavWidgetHost?
    #if os(iOS)
    private let manager = CLLocationManager()
    #endif

    private override init() {
        super.init()
        #if os(iOS)
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        // Leaving the app is when a save matters most
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkpoint(force: true) }
        }
        #endif
    }

    public var isActive: Bool { phase == .running || phase == .paused }
    public var movingSeconds: Double { track?.movingSeconds(at: now) ?? 0 }
    public var distance: Double { track?.distance ?? 0 }
    public var currentPace: Double? {
        // Last ~400 m when there's that much, else the whole run
        guard let samples = track?.samples, let last = samples.last else { return nil }
        if let from = samples.last(where: { last.meters - $0.meters >= 400 }) {
            return RunMath.pace(seconds: last.seconds - from.seconds, meters: last.meters - from.meters, unit: unit)
        }
        return RunMath.pace(seconds: movingSeconds, meters: distance, unit: unit)
    }

    // MARK: - Control

    public func start(context: WidgetContext, unit: RunUnit, followers: [RunFollower] = [],
                      coach: Bool = false, coachIntensity: MotivationIntensity = .savage) {
        guard !isActive else { return }
        coachOn = coach; self.coachIntensity = coachIntensity; coachedSplits = 0
        clientKey = UUID().uuidString
        followersWaiting = followers
        followersTold = []
        liveNoSignal = false
        lastLiveAttempt = .distantPast
        self.context = context
        self.host = context.host
        liveRun = nil; newCheer = nil; seenCheers = []; lastSyncedSplits = 0; watcherNames = []
        self.unit = unit
        problem = nil
        #if os(iOS)
        switch manager.authorizationStatus {
        case .denied, .restricted: problem = .locationDenied; return
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        guard CLLocationManager.locationServicesEnabled() else { problem = .locationOff; return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        track = RunTrack(startedAt: Date())
        waitingForGPS = true
        phase = .running
        startTicker()
        pushLive(force: true)
        checkpoint(force: true)
        inviteChosenFollowers()
    }

    // MARK: - Surviving the app closing

    /// The app reopened with a run saved on this phone: pick it back up.
    /// Safe to call any time (launch, the run page); does nothing while a run
    /// is going or when there's none to resume.
    public func restoreIfNeeded(host: FavWidgetHost) {
        guard !isActive, let userId = host.currentUserId,
              let saved = RunCheckpointFile(userId: userId).loadResumable(for: userId) else { return }
        restoreHost = host
        self.host = host
        unit = saved.unit
        coachOn = saved.coachOn
        coachIntensity = saved.coachIntensity
        coachedSplits = saved.coachedSplits
        clientKey = saved.clientKey
        track = saved.track
        phase = saved.track.isPaused ? .paused : .running
        problem = nil
        finishRequested = false
        waitingForGPS = !saved.track.isPaused
        #if os(iOS)
        if CLLocationManager.locationServicesEnabled(), manager.authorizationStatus != .denied, manager.authorizationStatus != .restricted {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            problem = .locationDenied
        }
        #endif
        startTicker()
        pushLive(force: true)
        pendingLiveRunId = saved.liveRunId
    }

    /// The run page opened: the session gets the page's context back (for
    /// live watching and the coach) and a run saved before the app closed is
    /// picked up if launch didn't already.
    public func attach(_ context: WidgetContext) {
        restoreIfNeeded(host: context.host)
        guard isActive else { return }
        self.context = context
        self.host = context.host
        restoreHost = nil
        if let id = pendingLiveRunId {
            pendingLiveRunId = nil
            Task { @MainActor in
                if let run = try? await RunShareClient(context: context).get(id), self.isActive, self.liveRun == nil {
                    self.liveRun = run
                    self.lastLiveSync = .distantPast
                    self.syncLiveIfDue(force: true)
                }
            }
        }
    }

    /// The shared run to reconnect to once a page gives us a context
    private var pendingLiveRunId: String?

    private func checkpoint(force: Bool = false) {
        guard isActive, let track, let userId = host?.currentUserId else { return }
        guard force || Date().timeIntervalSince(lastCheckpoint) >= Self.checkpointInterval else { return }
        lastCheckpoint = Date()
        let saved = RunCheckpoint(userId: userId, track: track, unit: unit, coachOn: coachOn, coachIntensity: coachIntensity,
                                  coachedSplits: coachedSplits, clientKey: clientKey, liveRunId: liveRun?.id ?? pendingLiveRunId)
        let file = RunCheckpointFile(userId: userId)
        Task.detached(priority: .utility) { try? file.save(saved) }
    }

    private func clearCheckpoint() {
        guard let userId = host?.currentUserId else { return }
        RunCheckpointFile(userId: userId).clear()
        pendingLiveRunId = nil
        restoreHost = nil
    }

    /// The run is live for the followers picked before it: their "watch
    /// live" push goes out now, nothing to tap mid-run.
    private func inviteChosenFollowers() {
        guard !followersWaiting.isEmpty else { return }
        attemptLive()
    }

    /// More people to tell mid-run (the invite sheet). Queued like the
    /// followers picked before the run, so a weak signal only delays them.
    public func queueInvites(_ people: [RunFollower]) {
        let known = Set((followersWaiting + followersTold).map(\.id))
        let fresh = people.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        followersWaiting += fresh
        attemptLive()
    }

    /// Every second from the ticker: try again once the last try is 15 s old.
    private func retryLiveIfDue() {
        guard isActive, !followersWaiting.isEmpty, !attemptingLive,
              Date().timeIntervalSince(lastLiveAttempt) >= Self.liveRetryInterval else { return }
        attemptLive()
    }

    /// Make the run watchable (the server returns the same run on a retry)
    /// and tell everyone waiting. Failures leave them waiting for the next try.
    func attemptLive() {
        guard let context, isActive, !attemptingLive else { return }
        attemptingLive = true
        lastLiveAttempt = Date()
        Task { @MainActor in
            defer { attemptingLive = false }
            do {
                let run = try await shareLive()
                let batch = followersWaiting
                if !batch.isEmpty {
                    _ = try await RunShareClient(context: context).invite(run.id, userIds: batch.map(\.id))
                    let sent = Set(batch.map(\.id))
                    followersWaiting.removeAll { sent.contains($0.id) }
                    followersTold += batch
                    context.track("run_followers_invited", ["count": "\(batch.count)"])
                }
                liveNoSignal = false
            } catch {
                liveNoSignal = true
                context.track("run_live_retry", ["waiting": "\(followersWaiting.count)"])
            }
        }
    }

    public func togglePause() {
        guard var t = track else { return }
        if phase == .running { t.pause(at: Date()); phase = .paused } else if phase == .paused { t.resume(at: Date()); phase = .running }
        track = t
        now = Date()
        pushLive(force: true)
        checkpoint(force: true)
    }

    /// From the lock screen: pause and let the run page show the summary.
    public func requestFinish() {
        if phase == .running { togglePause() }
        finishRequested = true
    }

    /// Stops tracking and hands back the run to save (nil if nothing moved).
    public func finish() -> RunTrack? {
        guard var t = track else { return nil }
        if !t.isPaused { t.pause(at: Date()) }
        stopHardware()
        phase = .finished
        finishRequested = false
        host?.runLiveActivity(nil)
        clearCheckpoint()
        let done = t
        track = nil
        phase = .idle
        return done.distance > 0 || done.movingSeconds(at: Date()) > 0 ? done : nil
    }

    public func discard() {
        stopHardware()
        clearCheckpoint()
        track = nil
        phase = .idle
        finishRequested = false
        host?.runLiveActivity(nil)
    }

    private func stopHardware() {
        ticker?.invalidate(); ticker = nil
        CoachVoice.shared.stop()
        #if os(iOS)
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.pushLive(force: false)
                self.syncLiveIfDue()
                self.retryLiveIfDue()
            }
        }
    }

    /// The lock screen: on changes, and every 5 s while running (its clock
    /// ticks by itself in between).
    private func pushLive(force: Bool) {
        guard let host, isActive else { return }
        guard force || Date().timeIntervalSince(lastLivePush) >= 5 else { return }
        lastLivePush = Date()
        let moving = movingSeconds
        host.runLiveActivity(WidgetRunLiveUpdate(
            distance: RunMath.distanceText(distance, unit: unit), unit: unit.label,
            pace: RunMath.paceText(currentPace), movingSeconds: moving,
            clockStart: phase == .running ? Date().addingTimeInterval(-moving) : nil,
            isPaused: phase == .paused))
    }

    // MARK: - Watching live

    /// Makes this run watchable (once); returns it so the caller can invite.
    func shareLive() async throws -> SharedRun {
        if let liveRun { return liveRun }
        guard let context, let track else { throw URLError(.cancelled) }
        let run = try await RunShareClient(context: context).startLive(unit: unit, startedAt: track.startedAt, clientKey: clientKey)
        liveRun = run
        lastLiveSync = .distantPast
        syncLiveIfDue(force: true)
        return run
    }

    /// Every 30 s, and right after each mile/km (watchers get that push).
    private func syncLiveIfDue(force: Bool = false) {
        guard let liveRun, let context, let track, !syncing else { return }
        let splits = RunMath.splits(track.samples, unit: unit)
        // Every 30 s; every 10 s while nobody has joined yet, so the first
        // "Sal is watching" shows up quickly
        let interval: TimeInterval = watcherNames.isEmpty ? 10 : 30
        guard force || splits.count > lastSyncedSplits || Date().timeIntervalSince(lastLiveSync) >= interval else { return }
        syncing = true
        lastLiveSync = Date()
        var body: [String: Any] = [
            "distanceM": track.distance, "movingSec": track.movingSeconds(at: Date()), "splits": splits,
            "route": RunGeo.encode(RunGeo.simplify(track.points.map { ($0.latitude, $0.longitude) })),
            "isPaused": phase == .paused
        ]
        if let last = track.points.last { body["lat"] = last.latitude; body["lng"] = last.longitude }
        let id = liveRun.id
        Task { @MainActor in
            defer { syncing = false }
            if let reply = try? await RunShareClient(context: context).progress(id, body: body) {
                lastSyncedSplits = splits.count
                watcherNames = reply.watchers
                for cheer in RunShare.newCheers(reply.cheers, seen: seenCheers) {
                    seenCheers.insert(RunShare.key(cheer))
                    newCheer = cheer
                    context.host.haptic(.success)
                }
            }
        }
    }

    /// The run was saved: watchers get the finish push and keep the run.
    func finishLive(_ record: RunRecord) {
        guard let liveRun, let context else { return }
        let id = liveRun.id
        Task { try? await RunShareClient(context: context).finish(id, body: RunShareClient.summary(record, unit: unit)) }
    }

    /// The run was thrown away: so is the shared one.
    func cancelLive() {
        guard let liveRun, let context else { return }
        let id = liveRun.id
        self.liveRun = nil
        Task { try? await RunShareClient(context: context).cancel(id) }
    }

    /// The finished run's shared id, for posting it to activity.
    var sharedRunId: String? { liveRun?.id }

    fileprivate func received(_ fix: RunFix) {
        guard var t = track else { return }
        if t.add(fix) { waitingForGPS = false }
        track = t
        checkpoint()
        coachIfMileDone()
    }

    /// A mile (or km) just ticked over: Coach Mane says how it went, then
    /// gives you grief. Only the newest one, never a backlog.
    private func coachIfMileDone() {
        guard phase == .running, let track, Int(track.distance / unit.meters) > coachedSplits else { return }
        let splits = RunMath.splits(track.samples, unit: unit)
        guard splits.count > coachedSplits else { return }
        coachedSplits = splits.count
        guard coachOn else { return }
        CoachVoice.shared.say(CoachRunCalls.call(splits: splits, index: splits.count - 1, unit: unit, intensity: coachIntensity), intensity: coachIntensity, context: context)
        context?.track("run_coach_spoke", ["split": "\(splits.count)"])
    }
}

#if os(iOS)
extension RunSession: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map {
            RunFix(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, time: $0.timestamp, accuracy: $0.horizontalAccuracy)
        }
        Task { @MainActor in fixes.forEach { self.received($0) } }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted, self.isActive { self.problem = .locationDenied }
        }
    }
}
#endif

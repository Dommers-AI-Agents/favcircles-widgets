import SwiftUI
import FavWidgetsCore

/// FavRun (Wes, 2026-10-06): GPS-tracked runs with a live map,
/// distance, time and pace (also on the lock screen via the app's Live
/// Activity), mile/km splits, history and personal bests. Runs are kept by
/// month and never pruned.
public struct RunWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "run",
        title: "FavRun",
        subtitle: "Track your runs on a map",
        symbolName: "figure.run",
        accentHex: "#DD6B20",
        category: .fitness,
        storage: .monthly,
        schemaVersion: RunSettings.schemaVersion,
        shareBlurb: "Track your runs with GPS: route map, pace, splits and personal bests."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(RunCardView(context: context, settings: context.state(RunSettings.self),
                            month: context.month(RunMonth.self, context.currentMonth)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(RunFullView(context: context, settings: context.state(RunSettings.self)))
    }

    /// The latest run (this month or last), with its route.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let settings = context.state(RunSettings.self)
        await settings.loadIfNeeded()
        var latest: RunRecord?
        for key in [context.currentMonth, context.currentMonth.previous] {
            let month = context.month(RunMonth.self, key)
            await month.loadIfNeeded()
            if let run = month.model.runs.max(by: { $0.startedAt < $1.startedAt }), run.startedAt > (latest?.startedAt ?? .distantPast) { latest = run }
        }
        guard let latest else { return nil }
        return .run(latest, unit: settings.model.unit, mapJPEG: await RunMapSnapshot.jpeg(latest.coordinates), calendar: context.calendar)
    }
}

/// "3.1 mi this week · last run Tue, 5K in 26:40" + Start.
struct RunCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<RunSettings>
    @ObservedObject var month: WidgetStateController<RunMonth>
    @ObservedObject private var session = RunSession.shared

    var body: some View {
        let theme = context.theme
        let unit = settings.model.unit
        WidgetCard(context: context, action: nil) {
            VStack(alignment: .leading, spacing: 6) {
                if session.isActive {
                    WidgetUI.summary("\(session.phase == .paused ? "Paused" : "Running") · \(RunMath.distanceText(session.distance, unit: unit)) \(unit.label) · \(RunMath.clock(session.movingSeconds))", theme: theme)
                } else if let last = month.model.runs.max(by: { $0.startedAt < $1.startedAt }) {
                    let week = month.model.runs.filter { context.calendar.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear) }
                        .reduce(0) { $0 + $1.distanceMeters }
                    WidgetUI.summary("\(RunMath.distanceText(week, unit: unit)) \(unit.label) this week", theme: theme)
                    Text("Last run \(last.startedAt.formatted(.dateTime.weekday(.abbreviated))): \(RunMath.distanceText(last.distanceMeters, unit: unit)) \(unit.label) in \(RunMath.clock(last.movingSeconds))")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                } else {
                    WidgetUI.summary("Tap to start your first run", theme: theme)
                }
            }
        }
        .task { await settings.loadIfNeeded(); await month.loadIfNeeded() }
    }
}

/// Start, the run in progress, or history.
struct RunFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<RunSettings>
    @ObservedObject private var session = RunSession.shared
    @State private var months: [MonthKey] = []
    @State private var finished: RunRecord?
    /// A shared run being watched (from the Watching list, a push, a link or the feed)
    @State private var watching: WatchTarget?
    /// The run just saved, offered for posting to activity
    @State private var toPost: PostTarget?

    struct WatchTarget: Identifiable { let id: String }
    struct PostTarget: Identifiable { let id = UUID(); let record: RunRecord; let sharedRunId: String? }

    var body: some View {
        Group {
            if session.isActive {
                ActiveRunView(context: context, unit: settings.model.unit, onFinish: finish)
            } else {
                RunHomeView(context: context, settings: settings, onStart: start)
            }
        }
        .background(context.theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await settings.loadIfNeeded() }
        .task { await openLaunchedRun() }
        .onChange(of: session.finishRequested) { requested in if requested { finish() } }
        .sheet(item: $finished) { run in
            RunSummaryView(context: context, run: run, unit: settings.model.unit, isNew: true,
                           onSave: { save(run) }, onDiscard: { RunSession.shared.cancelLive(); finished = nil })
        }
        .sheet(item: $watching) { target in RunWatchView(context: context, runId: target.id) }
        .sheet(item: $toPost) { target in
            RunPostSheet(context: context, record: target.record, unit: settings.model.unit, sharedRunId: target.sharedRunId,
                         settings: settings) {}
        }
    }

    private func start() {
        context.track("run_start")
        context.host.haptic(.success)
        RunSession.shared.start(context: context, unit: settings.model.unit, followers: settings.model.followerList,
                                coach: settings.model.coachOn, coachIntensity: settings.model.coachLevel)
    }

    private func finish() {
        guard let track = RunSession.shared.finish() else { return }
        finished = RunRecord.from(track, endedAt: Date(), weightKg: settings.model.weightKg)
    }

    private func save(_ run: RunRecord) {
        let month = context.month(RunMonth.self, MonthKey(run.startedAt, calendar: context.calendar))
        Task {
            await month.loadIfNeeded()
            month.update { $0.runs.insert(run, at: 0) }
            await month.flush()
        }
        context.track("run_saved", ["meters": String(Int(run.distanceMeters))])
        context.host.haptic(.success)
        // Watchers get the finish and keep the run
        RunSession.shared.finishLive(run)
        let sharedId = RunSession.shared.sharedRunId
        finished = nil
        // Then offer to post it (after the summary sheet has gone)
        Task { @MainActor in
            await context.waitForPageToSettle()
            toPost = PostTarget(record: run, sharedRunId: sharedId)
        }
    }

    /// A "watch my run" push, a feed row or a link opened FavRun.
    private func openLaunchedRun() async {
        if let id = context.launchRunId {
            context.launchRunId = nil
            await context.waitForPageToSettle()
            watching = WatchTarget(id: id)
        } else if let token = context.launchRunToken {
            context.launchRunToken = nil
            if let run = try? await RunShareClient(context: context).join(token: token) {
                await context.waitForPageToSettle()
                watching = WatchTarget(id: run.id)
            } else {
                context.host.presentAlert(WidgetAlert(title: "Can't open that run", message: "The link may be old, or the run was deleted."))
            }
        }
    }
}

/// Map, big numbers, Pause / Resume / Finish.
struct ActiveRunView: View {
    let context: WidgetContext
    let unit: RunUnit
    let onFinish: () -> Void
    @ObservedObject private var session = RunSession.shared
    @State private var confirmEnd = false
    @State private var showInvite = false

    var body: some View {
        let theme = context.theme
        let coords = session.track?.points.map { ($0.latitude, $0.longitude) } ?? []
        VStack(spacing: 0) {
            RunMapView(coordinates: coords, followsUser: true, tint: context.accent)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if let cheer = session.newCheer {
                        RunCheerBanner(cheer: cheer).padding(.top, 60)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .task(id: RunShare.key(cheer)) {
                                try? await Task.sleep(nanoseconds: 3_500_000_000)
                                withAnimation { session.newCheer = nil }
                            }
                    }
                }
                .animation(.spring(), value: session.newCheer)
                .overlay(alignment: .topTrailing) {
                    // Coach Mane on/off mid-run
                    Button {
                        session.coachOn.toggle()
                        context.host.haptic(.light)
                        if !session.coachOn { CoachVoice.shared.stop() }
                    } label: {
                        Text(session.coachOn ? "📣" : "🔇").font(.system(size: 22))
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(theme.background.opacity(0.9)))
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.coachOn ? "Mute Coach Mane" : "Turn on Coach Mane")
                    .padding(.top, 60).padding(.trailing, 14)
                }
            VStack(spacing: 14) {
                Button { showInvite = true } label: {
                    Text(inviteLabel)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(context.accent)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(Capsule().fill(context.accent.opacity(0.15)))
                }
                .buttonStyle(.plain)
                if let problem = session.problem {
                    Text(problem == .locationDenied
                         ? "Location is off for FavCircles. Turn it on in Settings to track your route."
                         : "Location Services are off. Turn them on in Settings.")
                        .font(.system(size: 14)).foregroundStyle(theme.danger).multilineTextAlignment(.center)
                } else if session.waitingForGPS {
                    Label("Finding GPS…", systemImage: "location.circle").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                Text(RunMath.distanceText(session.distance, unit: unit))
                    .font(.system(size: 64, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(theme.label)
                Text(unit == .miles ? "miles" : "kilometers").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                HStack {
                    stat(RunMath.clock(session.movingSeconds), "time")
                    stat(RunMath.paceText(session.currentPace), "pace /\(unit.label)")
                }
                HStack(spacing: 12) {
                    Button { RunSession.shared.togglePause(); context.host.haptic(.medium) } label: {
                        Label(session.phase == .paused ? "Resume" : "Pause", systemImage: session.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Capsule().fill(session.phase == .paused ? Color.green : context.accent))
                    }
                    if session.phase == .paused {
                        Button { confirmEnd = true } label: {
                            // Label-colored: black in light mode, white in dark (black vanished on dark)
                            Label("Finish", systemImage: "flag.checkered")
                                .font(.system(size: 17, weight: .bold)).foregroundStyle(theme.background)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(Capsule().fill(theme.label))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(theme.secondaryBackground)
        }
        .sheet(isPresented: $showInvite) { RunInviteSheet(context: context) }

        .confirmationDialog("Finish this run?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Finish and review") { onFinish() }
            Button("Discard run", role: .destructive) { RunSession.shared.cancelLive(); RunSession.shared.discard() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var inviteLabel: String {
        let names = session.watcherNames
        if names.isEmpty {
            return session.liveRun == nil ? "👀 Invite people to follow along" : "👀 Invited · waiting for them to join"
        }
        let shown = names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " +\(names.count - 2)" : "")
        return "👀 \(shown) watching · Invite more"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(context.theme.label)
            Text(label).font(.system(size: 12)).foregroundStyle(context.theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Start button, records, units and history.
struct RunHomeView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<RunSettings>
    let onStart: () -> Void
    @State private var loadedMonths: [MonthKey] = []
    @State private var runs: [RunRecord] = []
    @State private var opened: RunRecord?
    @State private var shared: [SharedRun] = []
    @State private var watchingId: String?
    @State private var choosingFollowers = false

    /// Coach Mane yells after every mile (2026-10-07)
    @ViewBuilder private func coachRow(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { settings.model.coachOn }, set: { on in
                settings.update { $0.coach = on }
                context.host.haptic(.light)
                context.track("run_coach_toggle", ["on": on ? "1" : "0"])
                if on { CoachVoice.shared.say(Self.coachHello(settings.model.coachLevel, unit: settings.model.unit), intensity: settings.model.coachLevel, context: context) } else { CoachVoice.shared.stop() }
            })) {
                HStack(spacing: 12) {
                    Text("📣").font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coach Mane").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.label)
                        Text("Yells at you after every \(settings.model.unit == .miles ? "mile" : "kilometer")")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
            .tint(context.accent)
            if settings.model.coachOn {
                Picker("Coach", selection: Binding(get: { settings.model.coachLevel }, set: { level in
                    settings.update { $0.coachIntensity = level }
                    CoachVoice.shared.say(Self.coachHello(level, unit: settings.model.unit), intensity: level, context: context)
                })) {
                    ForEach(MotivationIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
    }

    static func coachHello(_ level: MotivationIntensity, unit: RunUnit) -> String {
        let word = unit == .miles ? "mile" : "K"
        return level == .savage
            ? "Run, weakling! Why are you still standing there? Every \(word), I'll be in your ear. Move!"
            : "Coach Mane here. Every \(word), I'll be in your ear. Now get moving!"
    }

    var body: some View {
        let theme = context.theme
        let unit = settings.model.unit
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: onStart) {
                    VStack(spacing: 6) {
                        Image(systemName: "figure.run").font(.system(size: 34, weight: .bold))
                        Text("Start run").font(.system(size: 22, weight: .heavy))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 140)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(context.accent))
                }
                .buttonStyle(.plain)
                Button { choosingFollowers = true } label: {
                    HStack(spacing: 12) {
                        Text("👀").font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Followers").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            Text(settings.model.followersLine.map { "\($0) will follow this run" } ?? "Nobody yet — choose who can follow")
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(theme.label).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
                }
                .buttonStyle(.plain)
                coachRow(theme)
                Text("Your route, distance and pace show on the lock screen while you run. Friends you invite follow along on a map, get a ping every mile and can cheer you on.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)

                let others = shared.filter { !$0.isMine }
                if !others.isEmpty {
                    WidgetUI.header("Watching", theme: theme)
                    ForEach(others) { run in
                        Button { watchingId = run.id } label: {
                            HStack(spacing: 10) {
                                Text(run.isLive ? "● LIVE" : "🏁").font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(run.isLive ? .red : theme.secondaryLabel).frame(width: 52, alignment: .leading)
                                Text(RunShare.headline(run)).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
                            }
                            .padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Picker("Units", selection: Binding(get: { settings.model.unit }, set: { u in settings.update { $0.unit = u } })) {
                    Text("Miles").tag(RunUnit.miles); Text("Kilometers").tag(RunUnit.kilometers)
                }
                .pickerStyle(.segmented)

                let bests = RunRecords.bests(runs)
                if !bests.isEmpty {
                    WidgetUI.header("Personal bests", theme: theme)
                    ForEach(bests, id: \.label) { best in
                        HStack {
                            Text(best.label).foregroundStyle(theme.label)
                            Spacer()
                            Text(RunMath.clock(best.seconds)).monospacedDigit().foregroundStyle(theme.label)
                        }
                        .font(.system(size: 15))
                    }
                    if let longest = RunRecords.longest(runs) {
                        HStack {
                            Text("Longest run").foregroundStyle(theme.label); Spacer()
                            Text("\(RunMath.distanceText(longest.distanceMeters, unit: unit)) \(unit.label)").foregroundStyle(theme.label)
                        }
                        .font(.system(size: 15))
                    }
                }

                WidgetUI.header("History", theme: theme)
                if runs.isEmpty {
                    Text("Your runs show up here.").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                }
                ForEach(runs) { run in
                    Button { opened = run } label: { row(run, unit: unit) }.buttonStyle(.plain)
                    Divider().overlay(theme.separator)
                }
                if !runs.isEmpty, let oldest = loadedMonths.last {
                    Button("Show older runs") { Task { await load(oldest.previous) } }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
            }
            .padding(16)
        }
        .task {
            // Coach Mane's hello ready before the toggle is touched
            await settings.loadIfNeeded()
            for level in MotivationIntensity.allCases {
                CoachVoice.shared.prefetch(Self.coachHello(level, unit: settings.model.unit), intensity: level, context: context)
            }
            if loadedMonths.isEmpty {
                await load(context.currentMonth)
                await load(context.currentMonth.previous)
            }
            shared = (try? await RunShareClient(context: context).watching()) ?? []
        }
        .sheet(item: Binding(get: { watchingId.map { RunFullView.WatchTarget(id: $0) } }, set: { watchingId = $0?.id })) { t in
            RunWatchView(context: context, runId: t.id)
        }
        .sheet(isPresented: $choosingFollowers) {
            RunInviteSheet(context: context, choosing: (initial: settings.model.followerList, onDone: { chosen in
                settings.update { $0.followers = chosen }
            }))
        }
        .sheet(item: $opened) { run in
            RunSummaryView(context: context, run: run, unit: unit, isNew: false, onSave: {}, onDiscard: { opened = nil })
        }
    }

    private func load(_ key: MonthKey) async {
        guard !loadedMonths.contains(key) else { return }
        let month = context.month(RunMonth.self, key)
        await month.loadIfNeeded()
        loadedMonths.append(key)
        runs = (runs + month.model.runs).reduce(into: [RunRecord]()) { acc, r in if !acc.contains(where: { $0.id == r.id }) { acc.append(r) } }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func row(_ run: RunRecord, unit: RunUnit) -> some View {
        HStack(spacing: 12) {
            RunMapView(coordinates: run.coordinates, followsUser: false, tint: context.accent)
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10)).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(RunMath.distanceText(run.distanceMeters, unit: unit)) \(unit.label)")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(context.theme.label)
                Text("\(RunMath.clock(run.movingSeconds)) · \(RunMath.paceText(run.pace(unit)))/\(unit.label)")
                    .font(.system(size: 13)).foregroundStyle(context.theme.secondaryLabel)
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12)).foregroundStyle(context.theme.secondaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(context.theme.secondaryLabel)
        }
        .contentShape(Rectangle())
    }
}

/// A run's map, numbers and splits; for a new run, Save / Discard.
struct RunSummaryView: View {
    let context: WidgetContext
    let run: RunRecord
    let unit: RunUnit
    let isNew: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    @State private var sharing = false

    var body: some View {
        let theme = context.theme
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RunMapView(coordinates: run.coordinates, followsUser: false, tint: context.accent)
                        .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
                    HStack {
                        big(RunMath.distanceText(run.distanceMeters, unit: unit), unit.label)
                        big(RunMath.clock(run.movingSeconds), "time")
                        big(RunMath.paceText(run.pace(unit)), "/\(unit.label)")
                    }
                    Text("About \(run.calories) calories").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    let splits = run.splits(unit)
                    if !splits.isEmpty {
                        WidgetUI.header("Splits", theme: theme)
                        let fastest = splits.min() ?? 0
                        ForEach(Array(splits.enumerated()), id: \.offset) { i, s in
                            HStack {
                                Text("\(unit == .miles ? "Mile" : "Km") \(i + 1)").foregroundStyle(theme.label)
                                Spacer()
                                Text(RunMath.paceText(s)).monospacedDigit()
                                    .foregroundStyle(s == fastest && splits.count > 1 ? context.accent : theme.label)
                                    .fontWeight(s == fastest && splits.count > 1 ? .bold : .regular)
                            }
                            .font(.system(size: 15))
                        }
                    }
                    Button { share() } label: {
                        Label(sharing ? "Making the card…" : "Share this run", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .disabled(sharing)
                    if isNew {
                        WidgetUI.primaryButton("Save run", color: context.accent, action: onSave)
                        Button("Discard", role: .destructive, action: onDiscard)
                            .frame(maxWidth: .infinity).font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(run.startedAt.formatted(date: .abbreviated, time: .shortened))
            .toolbar { if !isNew { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDiscard) } } }
        }
        .interactiveDismissDisabled(isNew)
    }

    /// One bubble: the route, distance, time and pace, leading to FavRun.
    private func share() {
        sharing = true
        Task { @MainActor in
            let content = WidgetShareCardContent.run(run, unit: unit, mapJPEG: await RunMapSnapshot.jpeg(run.coordinates), calendar: context.calendar)
            sharing = false
            context.track("run_shared")
            context.host.share(WidgetShareKit.items(descriptor: context.descriptor, content: content))
        }
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(context.theme.label)
            Text(label).font(.system(size: 12)).foregroundStyle(context.theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

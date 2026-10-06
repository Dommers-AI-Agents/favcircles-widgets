import SwiftUI
import FavWidgetsCore

/// Map My Run (Wes, 2026-10-06): GPS-tracked runs with a live map,
/// distance, time and pace (also on the lock screen via the app's Live
/// Activity), mile/km splits, history and personal bests. Runs are kept by
/// month and never pruned.
public struct RunWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "run",
        title: "Map My Run",
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
        .onChange(of: session.finishRequested) { requested in if requested { finish() } }
        .sheet(item: $finished) { run in
            RunSummaryView(context: context, run: run, unit: settings.model.unit, isNew: true,
                           onSave: { save(run) }, onDiscard: { finished = nil })
        }
    }

    private func start() {
        context.track("run_start")
        context.host.haptic(.success)
        RunSession.shared.start(host: context.host, unit: settings.model.unit)
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
        finished = nil
    }
}

/// Map, big numbers, Pause / Resume / Finish.
struct ActiveRunView: View {
    let context: WidgetContext
    let unit: RunUnit
    let onFinish: () -> Void
    @ObservedObject private var session = RunSession.shared
    @State private var confirmEnd = false

    var body: some View {
        let theme = context.theme
        let coords = session.track?.points.map { ($0.latitude, $0.longitude) } ?? []
        VStack(spacing: 0) {
            RunMapView(coordinates: coords, followsUser: true, tint: context.accent)
                .frame(maxHeight: .infinity)
            VStack(spacing: 14) {
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
                            Label("Finish", systemImage: "flag.checkered")
                                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(Capsule().fill(Color.black))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(theme.secondaryBackground)
        }
        .confirmationDialog("Finish this run?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Finish and review") { onFinish() }
            Button("Discard run", role: .destructive) { RunSession.shared.discard() }
            Button("Keep going", role: .cancel) {}
        }
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
                Text("Your route, distance and pace show on the lock screen while you run.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)

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
            if loadedMonths.isEmpty {
                await load(context.currentMonth)
                await load(context.currentMonth.previous)
            }
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

    private func big(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(context.theme.label)
            Text(label).font(.system(size: 12)).foregroundStyle(context.theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

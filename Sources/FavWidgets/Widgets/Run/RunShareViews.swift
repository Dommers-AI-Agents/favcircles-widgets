import SwiftUI
import FavWidgetsCore
#if os(iOS)
import MapKit
import UIKit
#endif

// MARK: - Invite watchers (runner)

/// Pick connections to watch this run live (they get a push), or share the
/// link. The run becomes watchable on the first invite.
struct RunInviteSheet: View {
    let context: WidgetContext
    @State private var contacts: [WidgetContact] = []
    @State private var picked: Set<String> = []
    @State private var query = ""
    @State private var loading = true
    @State private var sending = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        let shown = contacts.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
        WidgetSheet(title: "Watch my run", theme: theme,
                    confirm: (label: sending ? "Inviting…" : (picked.isEmpty ? "Invite" : "Invite \(picked.count)"), enabled: !sending && !picked.isEmpty, action: send)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("They follow your route on a map, get a ping every mile, and can cheer you on. They keep the run when you're done.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    Button { shareLink() } label: {
                        Label("Share a link instead", systemImage: "link").font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    .buttonStyle(.plain)
                    WidgetUI.textField("Search your connections", text: $query, theme: theme, height: 40)
                    if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                    ForEach(shown) { person in
                        Button {
                            if picked.contains(person.id) { picked.remove(person.id) } else { picked.insert(person.id) }
                        } label: {
                            HStack {
                                Text(person.displayName).font(.system(size: 16)).foregroundStyle(theme.label)
                                Spacer()
                                Image(systemName: picked.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked.contains(person.id) ? context.accent : theme.secondaryLabel)
                            }
                            .padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .task {
            contacts = ((try? await context.host.fetchConnections()) ?? []).sorted { $0.displayName < $1.displayName }
            loading = false
        }
    }

    private func send() {
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let run = try await RunSession.shared.shareLive()
                let n = try await RunShareClient(context: context).invite(run.id, userIds: Array(picked))
                context.host.haptic(.success)
                context.track("run_watch_invited", ["count": "\(n)"])
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send the invites", message: "Check your connection and try again. Your run keeps going."))
            }
        }
    }

    private func shareLink() {
        Task { @MainActor in
            guard let run = try? await RunSession.shared.shareLive(), let url = URL(string: run.shareUrl) else { return }
            context.track("run_watch_link_shared")
            context.host.share([.text("I'm out for a run 🏃 Watch live in FavCircles: \(url.absoluteString)")])
        }
    }
}

/// A cheer popping up on the runner's screen.
struct RunCheerBanner: View {
    let cheer: SharedRun.Cheer
    var body: some View {
        HStack(spacing: 10) {
            Text(cheer.emoji).font(.system(size: 34))
            Text("\(cheer.fromName) is cheering you on!").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .shadow(radius: 10)
    }
}

// MARK: - Watching (followers)

/// Someone's run: live while they run (the map, the pace, the splits, cheer
/// buttons), the full run once they're done.
struct RunWatchView: View {
    let context: WidgetContext
    let runId: String
    @State private var run: SharedRun?
    @State private var failed: String?
    @State private var now = Date()
    @State private var cheered: String?
    @Environment(\.dismiss) private var dismiss
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var client: RunShareClient { RunShareClient(context: context) }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                if let run {
                    content(run, theme: theme)
                } else if let failed {
                    Text(failed).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center).padding(.top, 60).padding(.horizontal, 24)
                } else {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(run.map { $0.isMine ? "Your run" : "\($0.ownerName)'s run" } ?? "Run")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .refreshable { await load() }
        }
        .task {
            await load()
            // Live: refresh every 10 s while this is on screen
            while !Task.isCancelled, run?.isLive == true {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await load()
            }
        }
        .onReceive(tick) { now = $0 }
    }

    @ViewBuilder
    private func content(_ run: SharedRun, theme: WidgetTheme) -> some View {
        let unit = run.runUnit
        let seconds = RunShare.movingSeconds(run, now: now)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if run.isLive {
                    Text(run.isPaused ? "PAUSED" : "● LIVE").font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(run.isPaused ? Color.gray : Color.red))
                } else {
                    Text("🏁 Finished").font(.system(size: 13, weight: .heavy)).foregroundStyle(context.accent)
                }
                Text(RunShare.headline(run)).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            }
            RunWatchMap(route: run.coordinates, position: run.isLive ? run.position : nil, tint: context.accent)
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                stat(RunMath.distanceText(run.distanceM, unit: unit), unit.label, theme)
                stat(RunMath.clock(seconds), "time", theme)
                stat(RunMath.paceText(RunMath.pace(seconds: seconds, meters: run.distanceM, unit: unit)), "/\(unit.label)", theme)
            }
            if !run.isMine && !run.watching {
                WidgetUI.primaryButton("Follow along 👀", color: context.accent) { follow() }
            }
            if !run.isMine && run.isLive && run.watching {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cheer \(run.ownerName) on").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                    HStack(spacing: 8) {
                        ForEach(RunShare.cheerEmojis, id: \.self) { emoji in
                            Button { cheer(emoji) } label: {
                                Text(emoji).font(.system(size: 30)).frame(maxWidth: .infinity).frame(height: 52)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(cheered == emoji ? context.accent.opacity(0.3) : theme.secondaryBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !run.splits.isEmpty {
                WidgetUI.header("Splits", theme: theme)
                let fastest = run.splits.min() ?? 0
                ForEach(Array(run.splits.enumerated()), id: \.offset) { i, s in
                    HStack {
                        Text("\(unit == .miles ? "Mile" : "Km") \(i + 1)").foregroundStyle(theme.label)
                        Spacer()
                        Text(RunMath.paceText(s)).monospacedDigit()
                            .foregroundStyle(s == fastest && run.splits.count > 1 ? context.accent : theme.label)
                    }
                    .font(.system(size: 15))
                }
            }
            if !run.cheers.isEmpty {
                WidgetUI.header("Cheers", theme: theme)
                Text(run.cheers.suffix(12).map { "\($0.emoji) \($0.fromName)" }.joined(separator: "   "))
                    .font(.system(size: 14)).foregroundStyle(theme.label)
            }
            if !run.watchers.isEmpty {
                Text("👀 Watching: " + run.watchers.map(\.name).joined(separator: ", "))
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(16)
    }

    private func stat(_ value: String, _ label: String, _ theme: WidgetTheme) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(theme.label)
            Text(label).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        do { run = try await client.get(runId); failed = nil } catch {
            if run == nil { failed = "This run isn't shared with you, or it was deleted." }
        }
    }

    private func follow() {
        Task { @MainActor in
            if let r = try? await client.watch(runId) {
                run = r
                context.host.haptic(.success)
                context.track("run_watch_followed")
            }
        }
    }

    private func cheer(_ emoji: String) {
        cheered = emoji
        context.host.haptic(.success)
        context.track("run_cheer_sent")
        Task { @MainActor in
            try? await client.cheer(runId, emoji: emoji)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            cheered = nil
        }
    }
}

/// The route so far and where the runner is now.
struct RunWatchMap: View {
    let route: [(Double, Double)]
    let position: SharedRun.Position?
    let tint: Color

    var body: some View {
        ZStack {
            RunMapView(coordinates: route, followsUser: false, tint: tint)
            if position != nil { RunLiveBadge() }
        }
    }
}

/// "● Live" in the map's corner while the runner is out (the route's end is where they are).
struct RunLiveBadge: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Label("Live", systemImage: "location.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.red)).padding(8)
            }
            Spacer()
        }
    }
}

// MARK: - Post to activity (runner)

/// Share a finished run to the activity feed: connections or one Inner
/// Circle list (never "anyone on my lists" — Wes, 2026-10-02), with a map of
/// the route as the picture.
struct RunPostSheet: View {
    let context: WidgetContext
    let record: RunRecord
    let unit: RunUnit
    let sharedRunId: String?
    let onPosted: () -> Void
    @ObservedObject private var audience: WorkoutAudienceStore
    @State private var listId: String?          // nil = all connections
    @State private var posting = false
    @Environment(\.dismiss) private var dismiss

    init(context: WidgetContext, record: RunRecord, unit: RunUnit, sharedRunId: String?, onPosted: @escaping () -> Void) {
        self.context = context; self.record = record; self.unit = unit; self.sharedRunId = sharedRunId; self.onPosted = onPosted
        self.audience = WorkoutAudienceStore.shared(context)
    }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Post your run", theme: theme,
                    confirm: (label: posting ? "Posting…" : "Post", enabled: !posting, action: post)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    RunMapView(coordinates: record.coordinates, followsUser: false, tint: context.accent)
                        .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14)).allowsHitTesting(false)
                    Text("\(RunMath.distanceText(record.distanceMeters, unit: unit)) \(unit.label) · \(RunMath.clock(record.movingSeconds)) · \(RunMath.paceText(record.pace(unit)))/\(unit.label)")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(theme.label)
                    Text("Who sees it").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                    choice("My connections", selected: listId == nil) { listId = nil }
                    ForEach(audience.lists) { list in
                        choice("\(list.name) (\(list.count))", selected: listId == list.id) { listId = list.id }
                    }
                }
                .padding(16)
            }
        }
        .task { await audience.loadIfStale(context: context) }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16)).foregroundStyle(context.theme.label)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? context.accent : context.theme.secondaryLabel)
            }
            .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func post() {
        posting = true
        Task { @MainActor in
            defer { posting = false }
            var mapURL: URL?
            if let jpeg = await RunMapSnapshot.jpeg(record.coordinates) { mapURL = try? await context.host.uploadImage(jpeg) }
            do {
                _ = try await RunShareClient(context: context).post(runId: sharedRunId, record: record, unit: unit,
                                                                    audience: listId == nil ? "connections" : "innerCircle",
                                                                    listId: listId, mapImageUrl: mapURL)
                context.host.haptic(.success)
                context.track("run_posted", ["audience": listId == nil ? "connections" : "list"])
                onPosted()
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't post your run", message: "Check your connection and try again."))
            }
        }
    }
}

/// A picture of the route for the feed row.
enum RunMapSnapshot {
    static func jpeg(_ coords: [(Double, Double)]) async -> Data? {
        #if os(iOS)
        guard coords.count > 1 else { return nil }
        let points = coords.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        let line = MKPolyline(coordinates: points, count: points.count)
        let options = MKMapSnapshotter.Options()
        let rect = line.boundingMapRect
        options.mapRect = rect.insetBy(dx: -rect.size.width * 0.25 - 200, dy: -rect.size.height * 0.25 - 200)
        options.size = CGSize(width: 600, height: 400)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = UIGraphicsImageRenderer(size: options.size).image { ctx in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, p) in points.enumerated() {
                let pt = snapshot.point(for: p)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            UIColor(red: 0.867, green: 0.420, blue: 0.125, alpha: 1).setStroke()
            path.lineWidth = 6; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
        }
        return image.jpegData(compressionQuality: 0.85)
        #else
        return nil
        #endif
    }
}

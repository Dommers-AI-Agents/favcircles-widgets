import SwiftUI
import FavWidgetsCore

/// Sleep Score (Wes, 2026-10-08): last night scored 0–100 from Apple Health
/// (or logged by hand), stages when the Watch has them, and trends.
public struct SleepWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "sleep",
        title: "Sleep Score",
        subtitle: "How well you slept, from Apple Health",
        symbolName: "bed.double.fill",
        accentHex: "#6B46C1",
        category: .health,
        storage: .monthly,
        schemaVersion: SleepSettings.schemaVersion,
        shareBlurb: "A nightly sleep score from Apple Health, with trends."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(SleepCardView(context: context, settings: context.state(SleepSettings.self),
                              month: context.month(SleepMonth.self, context.currentMonth),
                              previous: context.month(SleepMonth.self, context.currentMonth.previous)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(SleepFullView(context: context, settings: context.state(SleepSettings.self),
                              month: context.month(SleepMonth.self, context.currentMonth),
                              previous: context.month(SleepMonth.self, context.currentMonth.previous)))
    }
}

/// Shared by the card and the full view.
@MainActor
enum SleepData {
    static func nights(_ month: WidgetStateController<SleepMonth>, _ previous: WidgetStateController<SleepMonth>) -> [SleepNight] {
        (previous.model.nights + month.model.nights).sorted { $0.day < $1.day }
    }

    /// Bedtimes of the 7 nights before `night`, for consistency.
    static func recentBedtimes(before night: SleepNight, in nights: [SleepNight]) -> [Date] {
        nights.filter { $0.day < night.day }.suffix(7).map(\.bedtime)
    }

    /// Pulls Health's nights into their month shards (manual ones stay).
    static func refreshFromHealth(context: WidgetContext, settings: WidgetStateController<SleepSettings>) async {
        guard settings.model.healthConnected, SleepHealthReader.isAvailable else { return }
        let nights = await SleepHealthReader.nights(days: 30, calendar: context.calendar)
        let byMonth = Dictionary(grouping: nights) { $0.day.monthKey }
        for (key, list) in byMonth {
            let shard = context.month(SleepMonth.self, key)
            await shard.loadIfNeeded()
            let before = shard.model
            var next = before
            for n in list { next.upsert(n) }
            if next != before { shard.update { $0 = next } }
        }
    }
}

struct SleepCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<SleepSettings>
    @ObservedObject var month: WidgetStateController<SleepMonth>
    @ObservedObject var previous: WidgetStateController<SleepMonth>

    var body: some View {
        let theme = context.theme
        let nights = SleepData.nights(month, previous)
        WidgetCard(context: context) {
            if let last = nights.last {
                let score = SleepScore.score(last, goalHours: settings.model.goalHours,
                                             recentBedtimes: SleepData.recentBedtimes(before: last, in: nights), calendar: context.calendar)
                HStack(spacing: 12) {
                    SleepRing(score: score.total, accent: context.accent, theme: theme, size: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(SleepScore.label(score.total)) · \(SleepScore.durationText(last.asleepMinutes))")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        if let avg = SleepScore.averageMinutes(Array(nights.suffix(7))) {
                            Text("7-night average \(SleepScore.durationText(avg))").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                }
            } else {
                WidgetUI.summary(settings.model.healthConnected ? "No sleep in Apple Health yet" : "Connect Apple Health or log last night", theme: theme)
            }
        }
        .task {
            await settings.loadIfNeeded(); await month.loadIfNeeded(); await previous.loadIfNeeded()
            await SleepData.refreshFromHealth(context: context, settings: settings)
        }
    }
}

struct SleepRing: View {
    let score: Int
    let accent: Color
    let theme: WidgetTheme
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle().stroke(theme.tertiaryBackground, lineWidth: size * 0.1)
            Circle().trim(from: 0, to: CGFloat(max(0, min(score, 100))) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.system(size: size * 0.34, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Sleep score \(score)")
    }
}

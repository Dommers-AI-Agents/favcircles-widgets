import SwiftUI
import FavWidgetsCore

struct SleepSoundsCardView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<SleepSoundsSettings>
    @ObservedObject var month: WidgetStateController<SleepSoundsMonth>
    @ObservedObject var engine: SleepSoundEngine

    var body: some View {
        let theme = context.theme
        let action = engine.isPlaying
            ? WidgetQuickAction("Stop", symbolName: "stop.fill") {
                context.track("widget_card_action", ["action": "stop"])
                engine.stop()
                context.host.haptic(.light)
            }
            : WidgetQuickAction("Play", symbolName: "play.fill") {
                context.track("widget_card_action", ["action": "play"])
                SleepSoundsLogging.restore(engine: engine, from: settings.model)
                engine.play()
                context.host.haptic(.light)
            }
        WidgetCard(context: context, action: action) {
            HStack(spacing: 8) {
                if engine.isPlaying {
                    SleepPulseDots(color: context.accent)
                }
                WidgetUI.summary(SleepSoundsCopy.cardSummary(
                    isPlaying: engine.isPlaying,
                    mixName: engine.isPlaying ? engine.mixName : (engine.hasBeenTouched ? engine.mixName : settings.model.startingName),
                    remaining: engine.remaining,
                    nightsThisMonth: month.model.nights(calendar: context.calendar)
                ), theme: theme)
            }
        }
        .task {
            SleepSoundsLogging.install(context: context, engine: engine)
            await settings.loadIfNeeded()
            await month.loadIfNeeded()
            SleepSoundsLogging.restore(engine: engine, from: settings.model)
        }
    }
}

/// Three small bars that breathe while sound is playing.
struct SleepPulseDots: View {
    let color: Color
    @State private var up = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: up ? [12, 7, 10][i] : [6, 12, 5][i])
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: up)
            }
        }
        .frame(height: 14)
        .onAppear { up = true }
    }
}

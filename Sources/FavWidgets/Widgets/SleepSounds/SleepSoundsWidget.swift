import SwiftUI
import FavWidgetsCore

/// Sleep Sounds: rain, ocean, fire, noise — mixed to taste, with a timer
/// that fades out, lock-screen controls, and playback that survives the
/// screen turning off. Every sound is synthesized on the phone.
///
/// Settings (saved mixes, last mix, timer) are the single document; each
/// month's shard logs the nights, never pruned.
public struct SleepSoundsWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "sleepsounds",
        title: "Sleep Sounds",
        subtitle: "Rain, ocean, fire — mix and drift off",
        symbolName: "moon.zzz.fill",
        accentHex: "#5B6CFF",
        category: .health,
        storage: .monthly
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(SleepSoundsCardView(
            context: context,
            settings: context.state(SleepSoundsSettings.self),
            month: context.month(SleepSoundsMonth.self, context.currentMonth),
            engine: SleepSoundEngine.shared
        ))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(SleepSoundsFullView(
            context: context,
            settings: context.state(SleepSoundsSettings.self),
            month: context.month(SleepSoundsMonth.self, context.currentMonth),
            engine: SleepSoundEngine.shared
        ))
    }
}

/// Glue between the engine and the documents: the engine reports a
/// finished night, the widget files it under the month it started in.
/// Installed by whichever view appears first; the context outlives both.
@MainActor
enum SleepSoundsLogging {
    static func install(context: WidgetContext, engine: SleepSoundEngine) {
        engine.onSessionEnded = { [weak context] session in
            guard let context else { return }
            let controller = context.month(SleepSoundsMonth.self, MonthKey(session.startedAt, calendar: context.calendar))
            Task { @MainActor in
                await controller.loadIfNeeded()
                controller.update { month in
                    if !month.sessions.contains(where: { $0.id == session.id }) { month.sessions.append(session) }
                }
                await controller.flush()
                context.track("sleepsounds_session", ["minutes": "\(session.seconds / 60)"])
            }
        }
    }

    /// Persists the mixer's state so Play on the card brings it back.
    static func remember(engine: SleepSoundEngine, settings: WidgetStateController<SleepSoundsSettings>) {
        settings.update { s in
            s.lastLevels = engine.levels
            s.lastMixName = engine.mixName
            s.timerMinutes = engine.timerMinutes
            s.masterVolume = engine.masterVolume
        }
    }

    /// Brings the saved state into a fresh engine (first launch only; a
    /// running engine keeps what it has).
    static func restore(engine: SleepSoundEngine, from settings: SleepSoundsSettings) {
        guard !engine.isPlaying, !engine.hasBeenTouched else { return }
        engine.load(levels: settings.startingLevels, name: settings.startingName)
        engine.setTimer(minutes: settings.timerMinutes)
        engine.setMasterVolume(settings.masterVolume)
        engine.hasBeenTouched = true
    }
}

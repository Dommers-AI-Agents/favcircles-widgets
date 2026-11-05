import Foundation
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Bedtime for Sleep Sounds (Wes, 2026-11-05). iOS won't let an app start
/// sound by itself at a set time, so:
///  - the reminder: a repeating local notification on the chosen days with a
///    Play button (and the whole banner) that opens Sleep Sounds and plays;
///  - fully automatic: the app's "Play Sleep Sounds" action (an audio
///    playback intent) calls `playNow`, which a Shortcuts automation can run
///    at that time without a tap.
public enum SleepSoundsBedtime {
    public static let categoryIdentifier = "SLEEP_BEDTIME"
    public static let playAction = "SLEEP_BEDTIME_PLAY"
    public static let notificationType = "sleep_bedtime"
    static let identifierPrefix = "sleep-bedtime-"
    static let documentId = "sleepsounds"

    // MARK: - Play when Sleep Sounds opens (the reminder's Play)

    nonisolated(unsafe) private static var playOnOpen = false

    /// The reminder was tapped: the next time Sleep Sounds shows, it plays
    public static func requestPlayOnOpen() { playOnOpen = true }

    static func takePlayRequest() -> Bool {
        defer { playOnOpen = false }
        return playOnOpen
    }

    // MARK: - Play now (the Shortcuts action)

    /// Loads the bedtime mix and starts it, with the saved timer and volume.
    /// Returns the mix's name, or nil when there was nothing to play.
    @MainActor
    @discardableResult
    public static func playNow(store: WidgetDataStore) async -> String? {
        let engine = SleepSoundEngine.shared
        if engine.isPlaying { return engine.mixName }
        let settings: SleepSoundsSettings = await {
            guard let document = try? await store.load(id: documentId),
                  let decoded = try? WidgetDocumentCodec.decode(SleepSoundsSettings.self, from: document.payload) else { return .empty }
            return decoded
        }()
        let mix = SleepBedtimePlan.mix(for: settings.bedtime, in: settings)
        engine.load(levels: mix.levels, name: mix.name)
        engine.setTimer(minutes: settings.timerMinutes)
        engine.setMasterVolume(settings.masterVolume)
        engine.hasBeenTouched = true
        engine.play()
        return engine.isPlaying ? mix.name : nil
    }

    // MARK: - The reminders

    /// App foreground: plans the reminders only when this phone has none
    /// (a reinstall gets them back). Never asks for permission.
    static func syncIfMissing(_ settings: SleepSoundsSettings) async {
        #if canImport(UserNotifications) && !os(macOS)
        guard settings.bedtime?.enabled == true else { return }
        let center = UNUserNotificationCenter.current()
        let hasAny = await center.pendingNotificationRequests().contains { $0.identifier.hasPrefix(identifierPrefix) }
        guard !hasAny else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        await sync(settings)
        #endif
    }

    /// Replaces this phone's bedtime reminders with the current plan, asking
    /// for permission the first time. False when notifications are denied.
    @discardableResult
    static func sync(_ settings: SleepSoundsSettings) async -> Bool {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let bedtime = settings.bedtime, bedtime.enabled else { return true }

        let current = await center.notificationSettings()
        var allowed = current.authorizationStatus == .authorized || current.authorizationStatus == .provisional
        if current.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return false }

        let mixName = SleepBedtimePlan.mix(for: bedtime, in: settings).name
        for trigger in SleepBedtimePlan.triggers(bedtime) {
            let content = UNMutableNotificationContent()
            content.title = SleepBedtimePlan.reminderTitle()
            content.body = SleepBedtimePlan.reminderBody(mixName: mixName)
            content.sound = .default
            content.threadIdentifier = "sleepsounds"
            // The app registers this category with a Play button that opens
            // Sleep Sounds and starts it
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = ["type": notificationType]
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(trigger.weekday ?? 0)",
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true))
            try? await center.add(request)
        }
        return true
        #else
        return true
        #endif
    }
}

import Foundation

/// "Keep questions on screen": iOS slides a banner away after a few seconds
/// unless the person sets FavCircles' Banner Style to Persistent — an app
/// can't choose that for them. The person being checked on gets a shortcut
/// to the setting while their banners are temporary (Wes, 2026-10-02).
public enum CareBannerTip {
    /// The phone's banner setting for this app, as UNNotificationSettings reports it
    public enum BannerStyle: Sendable { case temporary, persistent, none, unknown }

    public static func shouldShow(style: BannerStyle, isAskedSomething: Bool, dismissed: Bool) -> Bool {
        isAskedSomething && !dismissed && style == .temporary
    }

    public static let title = "Keep questions on screen"
    public static let body = "iPhone hides a question after a few seconds. In Settings → Banner Style, choose Persistent so each one stays until you answer."
    /// Opens this app's page in iOS Settings → Notifications
    public static let settingsURL = URL(string: "app-settings:notifications")!
}

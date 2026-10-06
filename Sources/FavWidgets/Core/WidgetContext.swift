import SwiftUI
import FavWidgetsCore

/// Holds one `WidgetStateController` per document id so a widget's card and
/// full view (and the tab's preload) share the same in-memory model.
@MainActor
public final class WidgetStateCache {
    private var controllers: [String: AnyObject] = [:]
    private let store: WidgetDataStore

    public init(store: WidgetDataStore) {
        self.store = store
    }

    public func controller<M: WidgetModel>(_ type: M.Type, documentId: String, schemaVersion: Int) -> WidgetStateController<M> {
        if let existing = controllers[documentId] as? WidgetStateController<M> {
            return existing
        }
        let controller = WidgetStateController<M>(documentId: documentId, schemaVersion: schemaVersion, store: store)
        controllers[documentId] = controller
        return controller
    }

    /// Every controller created so far, for flush/refresh sweeps.
    public var all: [any WidgetSyncing] {
        controllers.values.compactMap { $0 as? any WidgetSyncing }
    }
}

/// Type-erased view of a state controller for sweeps.
@MainActor
public protocol WidgetSyncing: AnyObject {
    var documentId: String { get }
    func flush() async
    func reload() async
    func adopt(_ document: WidgetDocument?)
    func restorePendingEdit()
}

extension WidgetStateController: WidgetSyncing {}

/// A photo the host hands a widget to start from, rather than making the
/// person pick one they are already looking at (Moments → "send as postcard").
public struct WidgetLaunchPhoto {
    public let image: PostcardPlatformImage
    /// Where the photo was taken, when the host knows. This is better evidence
    /// of the place than anything the widget could work out for itself.
    public let place: WidgetPlaceRef?

    public init(image: PostcardPlatformImage, place: WidgetPlaceRef? = nil) {
        self.image = image
        self.place = place
    }
}

/// What a widget's views receive: the host, the theme, its descriptor, and
/// access to its documents.
@MainActor
public final class WidgetContext: ObservableObject {
    public let host: FavWidgetHost
    public let theme: WidgetTheme
    public let descriptor: FavWidgetDescriptor
    public let calendar: Calendar
    let cache: WidgetStateCache

    /// Set by the tab so a card's primary action can open the full screen.
    public var openFullView: () -> Void = {}
    /// Set by the tab so a full view can close itself (after Send, etc.).
    public var closeFullView: () -> Void = {}

    /// A full view that wants the navigation bar's back button for itself
    /// (a live workout returning to the widget's home page) sets this while
    /// that screen is up and clears it after. Return true to consume the
    /// tap; false lets the host pop the widget as usual.
    public var handleBack: (() -> Bool)?

    /// Set by the host immediately before `openFullView` so a widget opens
    /// with a photo already in place. The widget clears it as it reads it, so
    /// the photo is used once and a later visit starts empty.
    public var launchPhoto: WidgetLaunchPhoto?
    /// A printed-postcard order the host wants shown (the "your postcard is
    /// printing" push). The postcard page reads and clears it on appear and
    /// opens that card's detail, topping up history from the server first
    /// if this phone never recorded the send.
    public var launchPostcardOrderId: String?

    /// A quote the host wants opened in the reel — the "quote of the day"
    /// push carries its id. The quotes page reads and clears it on appear.
    public var launchQuoteId: String?

    /// A shared workout the host wants shown (a tapped `workout_shared` row
    /// in the activity feed). The Workouts page reads and clears it on
    /// appear and opens the post, where the viewer can copy it as a routine.
    public var launchWorkoutPostId: String?

    /// A drink the host wants shown (a friend's sent drink, tapped in chat).
    /// The drink page reads and clears it on appear and opens that recipe.
    public var launchDrinkId: String?
    /// A Coach Mane line to open the Motivation page on (`MotivationLines.id`),
    /// from a notification's "Send to someone" or a friend's chat card.
    public var launchMotivationLineId: String?
    /// With `launchMotivationLineId`: also open the send sheet (the
    /// notification's Send action), rather than only showing the line.
    public var launchMotivationSend = false
    /// A received postcard to show (`postcardShares` token), from the printed
    /// card's QR or the web page's "Open it in the app".
    public var launchPostcardShareToken: String?
    /// An event invite link's token (`/app/event/<token>`, a push's invite):
    /// the Events page opens on the join screen.
    public var launchEventToken: String?
    /// An event to open (a "joined" or "new photos" push).
    public var launchEventId: String?

    /// A shared run to open in Map My Run (a "watch my run" push or feed row),
    /// or the link token of one to join. The Run page reads and clears them.
    public var launchRunId: String?
    public var launchRunToken: String?

    /// Await before presenting a launch target (a sheet or cover opened from
    /// launchWorkoutPostId and friends). On the first open the page is still
    /// being pushed, and a sheet presented mid-push flashed blank and closed;
    /// the second tap worked (Wes, 2026-10-02).
    public func waitForPageToSettle() async {
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    public init(host: FavWidgetHost, theme: WidgetTheme, descriptor: FavWidgetDescriptor, cache: WidgetStateCache, calendar: Calendar = .current) {
        self.host = host
        self.theme = theme
        self.descriptor = descriptor
        self.cache = cache
        self.calendar = calendar
    }

    /// The widget's settings/single document.
    public func state<M: WidgetModel>(_ type: M.Type) -> WidgetStateController<M> {
        cache.controller(type, documentId: descriptor.id, schemaVersion: descriptor.schemaVersion)
    }

    /// One month's shard of a monthly widget.
    public func month<M: WidgetModel>(_ type: M.Type, _ month: MonthKey) -> WidgetStateController<M> {
        cache.controller(type, documentId: WidgetShardPlanner.shardId(widgetId: descriptor.id, month: month), schemaVersion: descriptor.schemaVersion)
    }

    public var accent: Color { Color(hex: descriptor.accentHex) }

    /// Per-widget in-memory objects that outlive a single view (a fetched
    /// candidate pool, a running timer) but are not persisted. Shared by
    /// the card and the full view.
    private var transientObjects: [String: AnyObject] = [:]

    /// Drops every transient object (stores, polling pools). The tab calls
    /// this when the widget is switched off, so a hidden widget stops
    /// holding its feeds and quotes for the life of the app.
    public func clearTransients() {
        transientObjects.removeAll()
    }

    public func transient<T: AnyObject>(_ key: String, make: () -> T) -> T {
        if let existing = transientObjects[key] as? T { return existing }
        let object = make()
        transientObjects[key] = object
        return object
    }

    public func track(_ name: String, _ parameters: [String: String] = [:]) {
        var params = parameters
        params["widget_id"] = descriptor.id
        host.track(WidgetAnalyticsEvent(name, params))
    }

    public var today: DayKey { DayKey(Date(), calendar: calendar) }
    public var currentMonth: MonthKey { MonthKey(Date(), calendar: calendar) }
}

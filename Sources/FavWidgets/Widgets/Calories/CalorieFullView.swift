import SwiftUI
import FavWidgetsCore

/// Full screen: a day at a time (arrows cross months and load the other
/// month on demand), quick-add at the top, recents, the day's entries with
/// swipe-to-delete, and a 7-day bar row.
struct CalorieFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<CalorieSettings>
    @State private var day: DayKey
    @State private var showSettings = false

    init(context: WidgetContext, settings: WidgetStateController<CalorieSettings>) {
        self.context = context
        self.settings = settings
        _day = State(initialValue: context.today)
    }

    var body: some View {
        CalorieDayView(
            context: context,
            settings: settings,
            month: context.month(CalorieMonth.self, day.monthKey),
            weekMonth: context.month(CalorieMonth.self, day.adding(days: -6, calendar: context.calendar).monthKey),
            day: $day,
            showSettings: $showSettings
        )
        .task(id: day) {
            // Unstructured so a quick day step doesn't cancel an in-flight
            // load (reload() would record the cancellation as an error).
            // loadIfNeeded is a no-op once loaded, so per-day is cheap.
            let month = context.month(CalorieMonth.self, day.monthKey)
            let weekMonth = context.month(CalorieMonth.self, day.adding(days: -6, calendar: context.calendar).monthKey)
            Task { @MainActor in
                await settings.loadIfNeeded()
                await month.loadIfNeeded()
                await weekMonth.loadIfNeeded()
            }
        }
        .sheet(isPresented: $showSettings) {
            CalorieSettingsView(context: context, settings: settings)
        }
        .background(context.theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("Calories")
    }
}

// MARK: - Quick add


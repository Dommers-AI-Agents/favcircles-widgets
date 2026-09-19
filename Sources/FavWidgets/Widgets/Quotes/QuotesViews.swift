import SwiftUI
import FavWidgetsCore

/// The card: today's line if it has arrived, otherwise what to expect.
struct QuotesCardView: View {
    let context: WidgetContext
    @ObservedObject var store: QuotesStore

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 8) {
            if let quote = store.today {
                Text(quote.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.label)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let attribution = quote.attribution {
                    Text(attribution).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            } else if store.prefs.enabled {
                Text("Your quote arrives at \(QuoteCopy.friendly(store.prefs.time))")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            } else {
                Text("A good line to start the day")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                Text("Tap to choose your topics and time")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await store.loadIfNeeded(context: context) }
    }
}

/// The full view is the settings: on or off, what about, what time, and
/// whether it also goes to email.
struct QuotesFullView: View {
    let context: WidgetContext
    @ObservedObject var store: QuotesStore
    @State private var saving = false
    @State private var pickedTime = Date()
    @State private var timeLoaded = false

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let quote = store.today { todayCard(quote, theme: theme) }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { store.prefs.enabled },
                        set: { save(enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send me a quote each day")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            Text("As a notification, so alerts need to be on for Circles.")
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    .tint(context.accent)

                    if store.prefs.enabled {
                        Divider()
                        DatePicker("What time", selection: $pickedTime, displayedComponents: .hourAndMinute)
                            .font(.system(size: 15))
                            .tint(context.accent)
                            .onChange(of: pickedTime) { newValue in
                                let time = QuoteSettings.time(from: newValue, calendar: context.calendar)
                                if time != store.prefs.time { save(time: time) }
                            }
                        Text("In your own timezone.")
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)

                        Divider()
                        Toggle(isOn: Binding(
                            get: { store.prefs.email },
                            set: { save(email: $0) }
                        )) {
                            Text("Email it to me as well").font(.system(size: 15)).foregroundStyle(theme.label)
                        }
                        .tint(context.accent)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))

                if store.prefs.enabled { topics(theme: theme) }

                if let error = store.loadError {
                    Text(error).font(.system(size: 13)).foregroundStyle(theme.danger)
                }
            }
            .padding(16)
            .disabled(saving)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await store.loadIfNeeded(context: context)
            if !timeLoaded { pickedTime = store.prefs.timeAsDate; timeLoaded = true }
        }
        .refreshable { await store.load(context: context) }
    }

    private func todayCard(_ quote: DailyQuote, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Today", theme: theme)
            Text(quote.text)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            if let attribution = quote.attribution {
                Text(attribution).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent.opacity(0.10)))
    }

    private func topics(theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("What kind", theme: theme)
            Text("Pick as many as you like. Clearing them all means surprise me.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            ForEach(store.categories, id: \.id) { category in
                let on = store.prefs.categories.contains(category.id)
                Button { toggle(category.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(on ? context.accent : theme.separator)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.label).font(.system(size: 15)).foregroundStyle(theme.label)
                            Text(category.blurb).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ id: String) {
        var next = store.prefs.categories
        if let index = next.firstIndex(of: id) { next.remove(at: index) } else { next.append(id) }
        save(categories: next)
    }

    private func save(enabled: Bool? = nil, categories: [String]? = nil, time: String? = nil, email: Bool? = nil) {
        saving = true
        Task {
            defer { saving = false }
            do {
                let response = try await QuotesAPI.update(context: context, enabled: enabled, categories: categories, time: time, email: email)
                store.apply(response)
                context.host.haptic(.light)
                context.track("quotes_settings_saved")
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save that", message: error.localizedDescription))
                await store.load(context: context)
            }
        }
    }
}

enum QuoteCopy {
    /// "08:00" → "8:00 AM"
    static func friendly(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        let suffix = parts[0] >= 12 ? "PM" : "AM"
        let hour = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d %@", hour, parts[1], suffix)
    }
}

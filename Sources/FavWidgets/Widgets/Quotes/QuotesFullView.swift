import SwiftUI
import FavWidgetsCore

/// The full view is the settings: on or off, what about, which times of day
/// (one or several), and whether it also goes to email.
struct QuotesFullView: View {
    let context: WidgetContext
    @ObservedObject var store: QuotesStore
    @State private var saving = false
    /// Non-nil while the reel is up; the string is the quote to open on
    /// (empty means "start wherever the server wants").
    @State private var reelStart: String??

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let quote = store.today { todayCard(quote, theme: theme) }
                browseRow(theme: theme)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { store.prefs.enabled },
                        set: { save(enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send me quotes")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            Text("One a day, or a few at the times you pick. As notifications, so alerts need to be on for Circles.")
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    .tint(context.accent)

                    if store.prefs.enabled {
                        Divider()
                        timesSection(theme: theme)

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
        .task { await store.loadIfNeeded(context: context) }
        .refreshable { await store.load(context: context) }
        // The tapped "quote of the day" push. Read once and cleared, so
        // coming back to this page later doesn't reopen the reel.
        .task {
            guard let launched = context.launchQuoteId else { return }
            context.launchQuoteId = nil
            reelStart = .some(launched)
        }
        .quoteReelCover(isPresented: Binding(
            get: { reelStart != nil },
            set: { if !$0 { reelStart = nil } }
        )) {
            QuotesReelView(context: context,
                           startId: reelStart.flatMap { $0 },
                           onClose: { reelStart = nil })
        }
    }

    /// One row per time of day, each its own wheel; remove any but the last,
    /// add up to six.
    private func timesSection(theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.prefs.times.count == 1 ? "What time" : "What times")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            ForEach(Array(store.prefs.times.enumerated()), id: \.offset) { index, slot in
                HStack(spacing: 10) {
                    DatePicker("", selection: Binding(
                        get: { QuoteSettings.date(from: slot) },
                        set: { newValue in
                            let time = QuoteSettings.time(from: newValue, calendar: context.calendar)
                            guard time != slot else { return }
                            var next = store.prefs.times
                            next[index] = time
                            save(times: next)
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(context.accent)
                    Spacer()
                    if store.prefs.times.count > 1 {
                        Button {
                            var next = store.prefs.times
                            next.remove(at: index)
                            save(times: next)
                        } label: {
                            Image(systemName: "minus.circle").font(.system(size: 18)).foregroundStyle(theme.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if store.prefs.times.count < QuoteSettings.maxTimes {
                Button {
                    save(times: store.prefs.times + [QuoteCopy.nextSuggestedTime(after: store.prefs.times)])
                } label: {
                    Label("Add another time", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
            }
            Text("In your own timezone. Up to six a day.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    /// Always available, because the reel is worth reaching on a day when
    /// nothing has been sent yet — and on a phone that never enabled quotes.
    private func browseRow(theme: WidgetTheme) -> some View {
        Button { reelStart = .some(nil) } label: {
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble")
                Text("Browse quotes").font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(context.accent)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
        }
        .buttonStyle(.plain)
    }

    private func todayCard(_ quote: DailyQuote, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header(quote.slot.map { "Latest · \(QuoteCopy.friendly($0))" } ?? "Latest", theme: theme)
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
        .contentShape(Rectangle())
        // Opens on the quote that actually went out. Sends recorded before
        // the reel existed carry no id, and open wherever the server starts.
        .onTapGesture { reelStart = .some(quote.id) }
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

    private func save(enabled: Bool? = nil, categories: [String]? = nil, times: [String]? = nil, email: Bool? = nil) {
        saving = true
        Task {
            defer { saving = false }
            do {
                let response = try await QuotesAPI.update(context: context, enabled: enabled, categories: categories,
                                                          times: times.map { Array(Set($0)).sorted() }, email: email)
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
    /// "Your quotes arrive at 8:00 AM, 1:00 PM and 6:30 PM"
    static func schedule(_ times: [String]) -> String {
        let pretty = times.map(friendly)
        switch pretty.count {
        case 0: return "Pick a time"
        case 1: return "Your quote arrives at \(pretty[0])"
        case 2: return "Your quotes arrive at \(pretty[0]) and \(pretty[1])"
        default: return "Your quotes arrive at \(pretty.dropLast().joined(separator: ", ")) and \(pretty.last!)"
        }
    }

    /// A sensible next slot: a few hours after the latest one, wrapping
    /// before midnight rather than past it.
    static func nextSuggestedTime(after times: [String]) -> String {
        let minutes = times.compactMap { slot -> Int? in
            let p = slot.split(separator: ":").compactMap { Int($0) }
            return p.count == 2 ? p[0] * 60 + p[1] : nil
        }
        let last = minutes.max() ?? 8 * 60
        let next = last + 5 * 60 < 22 * 60 ? last + 5 * 60 : min(last + 60, 23 * 60)
        return String(format: "%02d:%02d", next / 60, next % 60)
    }

    /// "08:00" → "8:00 AM"
    static func friendly(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        let suffix = parts[0] >= 12 ? "PM" : "AM"
        let hour = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d %@", hour, parts[1], suffix)
    }
}

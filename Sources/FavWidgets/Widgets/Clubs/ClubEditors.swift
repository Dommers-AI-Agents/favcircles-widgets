import SwiftUI
import FavWidgetsCore

/// New club, or an organizer editing one: name, kind, emoji, what it is,
/// and where it usually meets.
struct ClubEditSheet: View {
    let context: WidgetContext
    /// nil = a new club
    let club: Club?
    let onSaved: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ClubKind = .run
    @State private var emoji = ClubKind.run.emoji
    @State private var emojiTouched = false
    @State private var about = ""
    @State private var homeSpot: ClubSpot?
    @State private var pickingSpot = false
    @State private var busy = false

    private static let emojiChoices = ["🏃", "🏃‍♀️", "🚶", "🚴", "🥾", "🏊", "🧘", "📚", "⚽️", "🎾", "🏀", "⛳️", "🎨", "🍷", "☕️", "🎲", "🤝", "🌄", "🐕", "📸"]

    var body: some View {
        let theme = context.theme
        let valid = !name.trimmingCharacters(in: .whitespaces).isEmpty
        WidgetSheet(title: club == nil ? "New club" : "Edit club", theme: theme,
                    confirm: (label: busy ? "Saving…" : (club == nil ? "Create" : "Save"), enabled: valid && !busy, action: save),
                    cancelDisabled: busy) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(emoji).font(.system(size: 60)).frame(maxWidth: .infinity)
                    WidgetUI.textField("Club name (Charlotte Run Club…)", text: $name, theme: theme)
                    WidgetUI.header("What kind", theme: theme)
                    FlowChips(items: ClubKind.allCases) { k in
                        Button {
                            kind = k
                            if !emojiTouched { emoji = k.emoji }
                        } label: {
                            Text("\(k.emoji) \(k.label.replacingOccurrences(of: " club", with: ""))")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Capsule().fill(k == kind ? context.accent.opacity(0.25) : theme.secondaryBackground))
                                .foregroundStyle(theme.label)
                        }
                        .buttonStyle(.plain)
                    }
                    WidgetUI.header("Emoji", theme: theme)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(Self.emojiChoices, id: \.self) { e in
                            Button { emoji = e; emojiTouched = true } label: {
                                Text(e).font(.system(size: 28)).frame(width: 50, height: 50)
                                    .background(Circle().fill(e == emoji ? context.accent.opacity(0.25) : theme.secondaryBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    WidgetUI.header("About", theme: theme)
                    TextField("Who it's for, the pace, what to bring…", text: $about, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 15))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                    WidgetUI.header("Where you usually meet", theme: theme)
                    Button { pickingSpot = true } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(context.accent)
                            Text(homeSpot?.name ?? "Pick a spot (optional)")
                                .foregroundStyle(homeSpot == nil ? theme.secondaryLabel : theme.label)
                            Spacer()
                            if homeSpot != nil {
                                Button { homeSpot = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryLabel) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    }
                    .buttonStyle(.plain)
                    if club == nil {
                        Text("Next you'll add the days and times you meet, and get a link for your group. Anyone with it can join; you can remove people or stop new members any time.")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $pickingSpot) {
            ClubSpotPicker(context: context, initial: homeSpot?.name ?? "") { homeSpot = $0 }
        }
        .onAppear {
            guard let club, name.isEmpty else { return }
            name = club.name
            kind = club.kind
            emoji = club.emoji
            emojiTouched = true
            about = club.description
            homeSpot = club.homeSpot
        }
    }

    private func save() {
        busy = true
        let client = ClubsClient(context: context)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { busy = false }
            do {
                let saved: Club
                if let club {
                    saved = try await client.update(club.id, [
                        "name": trimmedName, "kind": kind.rawValue, "emoji": emoji, "description": trimmedAbout,
                        "homeSpot": homeSpot?.body ?? NSNull()
                    ])
                } else {
                    saved = try await client.create(name: trimmedName, kind: kind, emoji: emoji, description: trimmedAbout, homeSpot: homeSpot)
                    context.track("club_created", ["kind": kind.rawValue])
                }
                context.host.haptic(.success)
                dismiss()
                onSaved(saved)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save the club", message: (error as NSError).localizedDescription))
            }
        }
    }
}

/// A weekly meetup: the day, the time, what it is, where, and notes.
struct ClubMeetupEditor: View {
    let context: WidgetContext
    let club: Club
    /// nil = a new meetup
    let meetup: ClubMeetup?
    let onSaved: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weekday = 6
    @State private var time = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var title = ""
    @State private var spot: ClubSpot?
    @State private var notes = ""
    @State private var pickingSpot = false
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: meetup == nil ? "Weekly meetup" : "Edit meetup", theme: theme,
                    confirm: (label: busy ? "Saving…" : "Save", enabled: !busy, action: save), cancelDisabled: busy) {
            Form {
                Section {
                    Picker("Every", selection: $weekday) {
                        ForEach(0..<7, id: \.self) { Text(ClubCopy.weekdayName($0)).tag($0) }
                    }
                    DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("In \(club.timeZone.localizedName(for: .generic, locale: .current) ?? club.timeZone.identifier) time.")
                }
                Section("What") {
                    TextField("Saturday long run", text: $title)
                    TextField("Notes (distance, pace, what to bring)", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                Section("Where") {
                    Button { pickingSpot = true } label: {
                        Text(spot?.name ?? (club.homeSpot.map { "\($0.name) (the usual spot)" } ?? "Pick a spot"))
                            .foregroundStyle(spot == nil ? theme.secondaryLabel : theme.label)
                    }
                    if spot != nil { Button("Use the usual spot", role: .destructive) { spot = nil } }
                }
                if let meetup {
                    Section {
                        Button("Delete this meetup", role: .destructive) { delete(meetup) }
                    }
                }
            }
        }
        .sheet(isPresented: $pickingSpot) {
            ClubSpotPicker(context: context, initial: spot?.name ?? "") { spot = $0 }
        }
        .onAppear {
            guard let meetup else { return }
            weekday = meetup.weekday
            let parts = meetup.time.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { time = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) ?? time }
            title = meetup.title
            spot = meetup.spot
            notes = meetup.notes ?? ""
        }
    }

    private var hhmm: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func save() {
        busy = true
        let client = ClubsClient(context: context)
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "\(ClubCopy.weekdayName(weekday)) \(club.kind == .book ? "meeting" : "meetup")" : title
        let body = ClubsClient.meetupBody(weekday: weekday, time: hhmm, title: finalTitle, spot: spot,
                                          notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        Task { @MainActor in
            defer { busy = false }
            do {
                let updated = meetup == nil ? try await client.addMeetup(club.id, body) : try await client.updateMeetup(club.id, meetup: meetup!.id, body)
                context.host.haptic(.success)
                dismiss()
                onSaved(updated)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save the meetup", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func delete(_ meetup: ClubMeetup) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let updated = try await ClubsClient(context: context).deleteMeetup(club.id, meetup: meetup.id)
                dismiss()
                onSaved(updated)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't delete it", message: (error as NSError).localizedDescription))
            }
        }
    }
}

/// A one-off event: a race, a social, a trip. Everyone gets a notification.
struct ClubEventEditor: View {
    let context: WidgetContext
    let club: Club
    let onSaved: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()) ?? Date()
    @State private var spot: ClubSpot?
    @State private var notes = ""
    @State private var pickingSpot = false
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        let valid = !title.trimmingCharacters(in: .whitespaces).isEmpty && startsAt > Date()
        WidgetSheet(title: "New event", theme: theme,
                    confirm: (label: busy ? "Saving…" : "Add", enabled: valid && !busy, action: save), cancelDisabled: busy) {
            Form {
                Section("What") {
                    TextField("Turkey Trot 5K, end-of-season party…", text: $title)
                    TextField("Notes (what to bring, where to park)", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                Section("When") {
                    DatePicker("Starts", selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Button { pickingSpot = true } label: {
                        Text(spot?.name ?? (club.homeSpot.map { "\($0.name) (the usual spot)" } ?? "Pick a spot"))
                            .foregroundStyle(spot == nil ? theme.secondaryLabel : theme.label)
                    }
                } header: { Text("Where") } footer: {
                    Text("Everyone in \(club.name) gets a notification about it.")
                }
            }
        }
        .sheet(isPresented: $pickingSpot) {
            ClubSpotPicker(context: context, initial: spot?.name ?? "") { spot = $0 }
        }
    }

    private func save() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let updated = try await ClubsClient(context: context).addEvent(
                    club.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: startsAt, spot: spot,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
                context.host.haptic(.success)
                context.track("club_event_added")
                dismiss()
                onSaved(updated)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add the event", message: (error as NSError).localizedDescription))
            }
        }
    }
}

/// Search a place (Apple Maps through the app) or just type a spot's name.
struct ClubSpotPicker: View {
    let context: WidgetContext
    let initial: String
    let onPick: (ClubSpot) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [WidgetPlaceCandidate] = []
    @State private var searching = false

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Meeting spot", theme: theme) {
            List {
                Section {
                    TextField("Park, trailhead, café, address…", text: $text)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { pick(ClubSpot(name: text.trimmingCharacters(in: .whitespaces))) } label: {
                            Label("Use \u{201C}\(text.trimmingCharacters(in: .whitespaces))\u{201D}", systemImage: "text.cursor")
                        }
                    }
                }
                if searching { ProgressView() }
                Section {
                    ForEach(results) { place in
                        Button {
                            pick(ClubSpot(name: place.name, address: place.address,
                                          lat: place.coordinate.latitude, lng: place.coordinate.longitude))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(theme.label)
                                if let address = place.address { Text(address).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                            }
                        }
                    }
                }
            }
        }
        .task(id: text) {
            // Search as they type, after a short pause
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
        .onAppear { if text.isEmpty { text = initial } }
    }

    private func search() async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { results = []; return }
        searching = true
        defer { searching = false }
        let here = await context.host.currentLocation()
        results = Array(((try? await context.host.searchPlaces(query, near: here)) ?? []).prefix(12))
    }

    private func pick(_ spot: ClubSpot) {
        context.host.haptic(.selection)
        onPick(spot)
        dismiss()
    }
}

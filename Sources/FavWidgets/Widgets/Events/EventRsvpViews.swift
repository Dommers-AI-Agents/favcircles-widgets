import SwiftUI
import FavWidgetsCore
#if os(iOS)
import ContactsUI
#endif

// Email invites and RSVPs, Evite-style (Wes, 2026-11-02). The server keeps
// the replies (services/eventGuestService); guests invited by email reply on
// a web page with no account. These are the in-app pieces: when/where on the
// event, your own Going/Maybe/Can't go, the guest list, invite by email,
// and a message to guests.

// MARK: - When / where / what

/// The when/where/details fields, shared by "New event" and "Edit details".
struct EventDetailsDraft: Equatable {
    var hasDate = false
    var start = EventTimes.suggestedStart(now: Date())
    var hasEnd = false
    var end = EventTimes.suggestedStart(now: Date()).addingTimeInterval(3 * 3600)
    var whereText = ""
    /// Set when they picked a search result (carries the spot)
    var location: EventLocation?
    var details = ""

    init() {}

    init(event: EventSummary) {
        if let start = event.startDate {
            hasDate = true
            self.start = start
            if let end = event.endDate { hasEnd = true; self.end = end } else { end = start.addingTimeInterval(3 * 3600) }
        }
        if let location = event.location {
            self.location = location
            whereText = location.address.isEmpty || location.address == location.name ? location.name : "\(location.name), \(location.address)"
        }
        details = event.detailsText
    }

    /// What the server takes: every field, so clearing one clears it.
    var requestBody: [String: Any] {
        var body: [String: Any] = ["timezone": TimeZone.current.identifier, "details": details.trimmingCharacters(in: .whitespacesAndNewlines)]
        body["startsAt"] = hasDate ? EventTimes.string(start) : NSNull()
        body["endsAt"] = hasDate && hasEnd && end > start ? EventTimes.string(end) : NSNull()
        let typed = whereText.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            body["location"] = NSNull()
        } else if let location, typedMatches(location, typed) {
            body["location"] = location.requestBody
        } else {
            body["location"] = EventLocation(name: typed).requestBody
        }
        return body
    }

    private func typedMatches(_ location: EventLocation, _ typed: String) -> Bool {
        typed == location.name || typed.hasPrefix(location.name)
    }
}

struct EventDetailsFields: View {
    let context: WidgetContext
    @Binding var draft: EventDetailsDraft
    @State private var results: [WidgetPlaceCandidate] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $draft.hasDate.animation()) {
                Label("Date and time", systemImage: "calendar").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            }
            .tint(context.accent)
            if draft.hasDate {
                DatePicker("Starts", selection: $draft.start, displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 15)).foregroundStyle(theme.label)
                Toggle("Add an end time", isOn: $draft.hasEnd.animation()).font(.system(size: 15)).foregroundStyle(theme.label).tint(context.accent)
                if draft.hasEnd {
                    DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: [.date, .hourAndMinute])
                        .font(.system(size: 15)).foregroundStyle(theme.label)
                }
            }
            Label("Where", systemImage: "mappin.and.ellipse").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            WidgetUI.textField("A place or an address", text: $draft.whereText, theme: theme)
                .onChange(of: draft.whereText) { text in search(text) }
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results.prefix(5)) { place in
                        Button { pick(place) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                                if let address = place.address, !address.isEmpty {
                                    Text(address).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            }
            Label("Details", systemImage: "text.alignleft").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            TextEditor(text: $draft.details)
                .font(.system(size: 15))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                .overlay(alignment: .topLeading) {
                    if draft.details.isEmpty {
                        Text("What to bring, the dress code, parking…").font(.system(size: 15))
                            .foregroundStyle(theme.secondaryLabel).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
                    }
                }
        }
    }

    /// Search places as they type (3+ letters, after a short pause)
    private func search(_ text: String) {
        searchTask?.cancel()
        if let picked = draft.location, text != picked.name, !text.hasPrefix(picked.name) { draft.location = nil }
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 3, draft.location == nil else { results = []; return }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let near = await context.host.currentLocation()
            results = (try? await context.host.searchPlaces(query, near: near)) ?? []
        }
    }

    private func pick(_ place: WidgetPlaceCandidate) {
        draft.location = EventLocation(name: place.name, address: place.address ?? "",
                                       lat: place.coordinate.latitude, lng: place.coordinate.longitude)
        draft.whereText = place.name
        results = []
        context.host.haptic(.selection)
    }
}

/// The coordinator changes when/where/what; guests can be told.
struct EventEditDetailsSheet: View {
    let context: WidgetContext
    let event: EventSummary
    let onSaved: (EventSummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDetailsDraft
    @State private var tellGuests = true
    @State private var busy = false

    init(context: WidgetContext, event: EventSummary, onSaved: @escaping (EventSummary) -> Void) {
        self.context = context
        self.event = event
        self.onSaved = onSaved
        _draft = State(initialValue: EventDetailsDraft(event: event))
    }

    private var hasGuests: Bool { event.emailGuestCount > 0 || event.members.count > 1 }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Event details", theme: theme,
                    confirm: (label: busy ? "Saving…" : "Save", enabled: !busy, action: save), cancelDisabled: busy) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EventDetailsFields(context: context, draft: $draft)
                    if hasGuests {
                        Toggle("Let guests know if the time or place changes", isOn: $tellGuests)
                            .font(.system(size: 14)).foregroundStyle(theme.label).tint(context.accent)
                    }
                }
                .padding(16)
            }
        }
    }

    private func save() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                var body = draft.requestBody
                body["notifyGuests"] = hasGuests && tellGuests
                let updated = try await EventsClient(context: context).update(event.id, body)
                context.host.haptic(.success)
                context.track("event_details_saved", ["date": draft.hasDate ? "1" : "0"])
                dismiss()
                onSaved(updated)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save", message: EventRsvpErrors.message(error)))
            }
        }
    }
}

/// When / where / details under the event's header, with calendar and directions.
struct EventWhenWhereCard: View {
    let context: WidgetContext
    let event: EventSummary
    var onEdit: (() -> Void)?

    var body: some View {
        let theme = context.theme
        if event.whenText != nil || event.whereText != nil || !event.detailsText.isEmpty || (event.isHost && !event.hasEnded) {
            VStack(alignment: .leading, spacing: 10) {
                if let when = event.whenText {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "calendar").foregroundStyle(context.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(when).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            if let url = event.calendarUrl.flatMap(URL.init(string:)) {
                                Button("Add to calendar") { context.host.openURL(url); context.track("event_calendar_added") }
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                            }
                        }
                    }
                }
                if let whereText = event.whereText {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(context.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(whereText).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            if let url = directionsURL {
                                Button("Directions") { context.host.openURL(url) }
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                            }
                        }
                    }
                }
                if !event.detailsText.isEmpty {
                    Text(event.detailsText).font(.system(size: 14)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
                }
                if event.isHost && !event.hasEnded, let onEdit {
                    Button { onEdit() } label: {
                        Label(event.whenText == nil && event.whereText == nil ? "Add a date, place and details" : "Edit details",
                              systemImage: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(context.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private var directionsURL: URL? {
        guard let location = event.location else { return nil }
        var parts = URLComponents(string: "https://maps.apple.com/")!
        if let c = location.coordinate {
            parts.queryItems = [URLQueryItem(name: "ll", value: "\(c.latitude),\(c.longitude)"), URLQueryItem(name: "q", value: location.name)]
        } else {
            parts.queryItems = [URLQueryItem(name: "q", value: event.whereText ?? location.name)]
        }
        return parts.url
    }
}

// MARK: - Your reply + the totals

/// "Are you going?" for members, and everyone's totals (tap for the list).
struct EventReplyCard: View {
    let context: WidgetContext
    let event: EventSummary
    let onUpdated: (EventSummary?) -> Void
    let onOpenGuests: () -> Void
    @State private var adults = 1
    @State private var kids = 0
    @State private var choice: EventRsvp?
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 12) {
            if !event.isHost && !event.hasEnded {
                Text(EventRsvpCopy.myReply(currentReply) ?? "Are you going?")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(theme.label)
                HStack(spacing: 8) {
                    ForEach(EventRsvp.choices, id: \.self) { option in
                        Button { send(option) } label: {
                            Text("\(option.emoji) \(option.label)")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(currentChoice == option ? .white : context.accent)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(currentChoice == option ? context.accent : context.accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }
                if currentChoice != .no {
                    HStack(spacing: 16) {
                        Stepper("Adults \(adults)", value: $adults, in: 1...20) { editing in if !editing { send(currentChoice) } }
                        Stepper("Kids \(kids)", value: $kids, in: 0...20) { editing in if !editing { send(currentChoice) } }
                    }
                    .font(.system(size: 14)).foregroundStyle(theme.label)
                }
            }
            Button { onOpenGuests() } label: {
                HStack {
                    Image(systemName: "person.3.fill").foregroundStyle(context.accent)
                    Text(EventRsvpCopy.summary(event.rsvpCounts) ?? "Guest list")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Guest list")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        .onAppear {
            adults = max(1, event.myRsvp?.adults ?? 1)
            kids = event.myRsvp?.kids ?? 0
        }
    }

    private var currentChoice: EventRsvp { choice ?? event.myRsvp?.rsvp ?? .yes }
    private var currentReply: EventMyRsvp { EventMyRsvp(rsvp: currentChoice, adults: adults, kids: kids) }

    private func send(_ option: EventRsvp) {
        let previous = choice
        choice = option
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                _ = try await EventsClient(context: context).rsvp(event.id, option, adults: adults, kids: kids, note: "")
                context.host.haptic(.success)
                context.track("event_rsvp", ["rsvp": option.rawValue])
                onUpdated(nil)
            } catch {
                choice = previous
                context.host.presentAlert(WidgetAlert(title: "Couldn't save your reply", message: EventRsvpErrors.message(error)))
            }
        }
    }
}

// MARK: - Guest list

struct EventGuestsSheet: View {
    let context: WidgetContext
    let event: EventSummary
    /// Something changed (an invite, a removal): refresh the event
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var list: EventGuestList?
    @State private var failed = false
    @State private var showInvite = false
    @State private var showMessage = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            List {
                if let list {
                    if event.isHost && !event.hasEnded {
                        Section {
                            Button { showInvite = true } label: { Label("Invite by email", systemImage: "envelope.badge") }
                            Button { showMessage = true } label: { Label("Message guests", systemImage: "text.bubble") }
                        } footer: {
                            if let left = list.emailsLeftToday {
                                Text("Guests reply from their email, no app needed. You can send \(left) more event emails today.")
                            }
                        }
                    }
                    ForEach([EventRsvp.yes, .maybe, .pending, .no], id: \.self) { rsvp in
                        let people = list.guests.filter { $0.rsvp == rsvp }
                        if !people.isEmpty {
                            Section("\(rsvp.emoji) \(rsvp.label) · \(rsvp == .pending || rsvp == .no ? list.counts.bucket(rsvp).replies : list.counts.bucket(rsvp).people)") {
                                ForEach(people) { guest in row(guest, theme: theme) }
                            }
                        }
                    }
                    if list.guests.count <= 1 && !event.isHost {
                        Text("No one else yet.").foregroundStyle(theme.secondaryLabel)
                    }
                } else if failed {
                    Text("Couldn't load the guest list. Pull to try again.").foregroundStyle(theme.secondaryLabel)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .refreshable { await load() }
            .widgetInlineNavigationTitle("Guest list")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task { await load() }
        .sheet(isPresented: $showInvite) {
            EventEmailInviteSheet(context: context, event: event, emailsLeft: list?.emailsLeftToday) { updated in
                list = updated
                onChanged()
            }
        }
        .sheet(isPresented: $showMessage) { EventMessageGuestsSheet(context: context, event: event) }
    }

    @ViewBuilder
    private func row(_ guest: EventGuest, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(guest.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                if guest.isHost == true { Text("Host").font(.system(size: 11, weight: .bold)).foregroundStyle(context.accent) }
                if guest.kind == "email" {
                    Image(systemName: "envelope").font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                        .accessibilityLabel("Invited by email")
                }
                Spacer()
                let party = EventRsvpCopy.partySize(adults: guest.adults, kids: guest.kids)
                if !party.isEmpty && (guest.rsvp == .yes || guest.rsvp == .maybe) {
                    Text(party).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            if let email = guest.email, email != guest.displayName {
                Text(email).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            if let note = guest.note, !note.isEmpty {
                Text("“\(note)”").font(.system(size: 13)).foregroundStyle(theme.label)
            }
            if guest.optedOut == true {
                Text("Asked not to get emails about this event").font(.system(size: 12)).foregroundStyle(theme.warning)
            }
        }
        .swipeActions(edge: .trailing) {
            if event.isHost && guest.isEmailGuest {
                Button(role: .destructive) { remove(guest) } label: { Label("Remove", systemImage: "trash") }
                if guest.optedOut != true && !event.hasEnded {
                    Button { resend(guest) } label: { Label("Resend", systemImage: "arrow.clockwise") }.tint(context.accent)
                }
            }
        }
    }

    private func load() async {
        do {
            list = try await EventsClient(context: context).guests(event.id)
            failed = false
        } catch {
            failed = true
        }
    }

    private func resend(_ guest: EventGuest) {
        Task { @MainActor in
            do {
                let sent = try await EventsClient(context: context).resend(event.id, guest: guest.id)
                context.host.presentAlert(WidgetAlert(title: sent ? "Sent again" : "Couldn't send",
                                                      message: sent ? "\(guest.displayName) has the invite again." : "Try again in a bit."))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: EventRsvpErrors.message(error)))
            }
        }
    }

    private func remove(_ guest: EventGuest) {
        Task { @MainActor in
            do {
                try await EventsClient(context: context).removeGuest(event.id, guest: guest.id)
                await load()
                onChanged()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't remove", message: EventRsvpErrors.message(error)))
            }
        }
    }
}

// MARK: - Invite by email

struct EventEmailInviteSheet: View {
    let context: WidgetContext
    let event: EventSummary
    let emailsLeft: Int?
    let onSent: (EventGuestList) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// Names for addresses picked from Contacts
    @State private var names: [String: String] = [:]
    @State private var message = ""
    @State private var busy = false

    private var parsed: (emails: [String], invalid: [String]) { EventRsvpCopy.parseEmails(text) }

    var body: some View {
        let theme = context.theme
        let found = parsed
        WidgetSheet(title: "Invite by email", theme: theme,
                    confirm: (label: busy ? "Sending…" : EventRsvpCopy.inviteEmailsButton(found.emails.count),
                              enabled: !busy && !found.emails.isEmpty, action: send),
                    cancelDisabled: busy) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("They get an invite with \(event.whenText == nil ? "the event" : "the date, place") and Going / Maybe / Can't go buttons. No app needed to reply.")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    if event.whenText == nil {
                        Label("Tip: add a date and place first so the invite says when and where.", systemImage: "lightbulb")
                            .font(.system(size: 13)).foregroundStyle(theme.warning)
                    }
                    #if os(iOS)
                    Button { pickContacts() } label: {
                        Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(context.accent)
                    #endif
                    Text("Email addresses").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                    TextEditor(text: $text)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Type or paste addresses, separated by commas or new lines").font(.system(size: 15))
                                    .foregroundStyle(theme.secondaryLabel).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
                            }
                        }
                    if !found.emails.isEmpty {
                        Text("\(found.emails.count) to invite: \(found.emails.prefix(6).map { names[$0] ?? $0 }.joined(separator: ", "))\(found.emails.count > 6 ? "…" : "")")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    if !found.invalid.isEmpty {
                        Text("These don't look like addresses: \(found.invalid.prefix(4).joined(separator: ", "))")
                            .font(.system(size: 13)).foregroundStyle(theme.warning)
                    }
                    Text("A note from you (optional)").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                    WidgetUI.textField("Hope you can make it!", text: $message, theme: theme)
                    if let emailsLeft {
                        Text("You can send \(emailsLeft) more event emails today.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(16)
            }
        }
    }

    #if os(iOS)
    private func pickContacts() {
        ContactEmailPicker.present { picked in
            var lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for contact in picked where !EventRsvpCopy.parseEmails(lines).emails.contains(contact.email) {
                lines += lines.isEmpty ? contact.email : "\n\(contact.email)"
                if !contact.name.isEmpty { names[contact.email] = contact.name }
            }
            text = lines
        }
    }
    #endif

    private func send() {
        let emails = parsed.emails
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await EventsClient(context: context).inviteByEmail(
                    event.id, guests: emails.map { (email: $0, name: names[$0] ?? "") }, message: message)
                context.host.haptic(.success)
                context.track("event_email_invites", ["count": "\(result.sent)"])
                onSent(result.list)
                dismiss()
                context.host.presentAlert(WidgetAlert(title: "Invites sent",
                    message: EventRsvpCopy.invitesSent(sent: result.sent, already: result.alreadyInvited, invalid: result.invalid.count)))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send invites", message: EventRsvpErrors.message(error)))
            }
        }
    }
}

// MARK: - Message guests

struct EventMessageGuestsSheet: View {
    let context: WidgetContext
    let event: EventSummary
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var audience = EventRsvpCopy.Audience.all
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Message guests", theme: theme,
                    confirm: (label: busy ? "Sending…" : "Send", enabled: !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: send),
                    cancelDisabled: busy) {
            Form {
                Picker("Send to", selection: $audience) {
                    ForEach(EventRsvpCopy.Audience.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Section {
                    TextEditor(text: $text).frame(minHeight: 140)
                } footer: {
                    Text("Email guests get it by email; people in the app get a notification.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
        }
    }

    private func send() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await EventsClient(context: context).messageGuests(event.id, text: text, audience: audience)
                context.host.haptic(.success)
                context.track("event_guest_message", ["audience": audience.rawValue])
                dismiss()
                let total = result.emailed + result.pushed
                context.host.presentAlert(WidgetAlert(title: "Message sent",
                    message: total == 0 ? "No one matched that group yet." : "Sent to \(total) \(total == 1 ? "person" : "people")."))
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: EventRsvpErrors.message(error)))
            }
        }
    }
}

// MARK: - Errors

enum EventRsvpErrors {
    /// The server's words when it sent some (limits, "only the coordinator"),
    /// otherwise the friendly line.
    static func message(_ error: Error) -> String {
        if let api = error as? WidgetAPIError, (400..<500).contains(api.status), !api.message.isEmpty { return api.message }
        return "Check your connection and try again."
    }
}

// MARK: - Contacts (iOS)

#if os(iOS)
/// Picks people with an email address from Contacts. The system picker runs
/// out of process, so no Contacts permission is asked for.
enum ContactEmailPicker {
    struct Picked { let name: String; let email: String }

    private final class Delegate: NSObject, CNContactPickerDelegate {
        let onPick: ([Picked]) -> Void
        init(onPick: @escaping ([Picked]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts.compactMap { contact in
                guard let email = contact.emailAddresses.first?.value as String? else { return nil }
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                return Picked(name: name, email: email.lowercased())
            })
            ContactEmailPicker.current = nil
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { ContactEmailPicker.current = nil }
    }

    private static var current: Delegate?

    @MainActor
    static func present(onPick: @escaping ([Picked]) -> Void) {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        let delegate = Delegate(onPick: onPick)
        current = delegate
        picker.delegate = delegate
        guard let top = topViewController() else { return }
        top.present(picker, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#endif

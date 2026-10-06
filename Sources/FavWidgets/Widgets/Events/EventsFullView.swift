import SwiftUI
import FavWidgetsCore

/// Your events, "Start an event", and the join screen a link or invite opens.
struct EventsFullView: View {
    let context: WidgetContext
    @ObservedObject var store: EventsStore

    @State private var creating = false
    @State private var openEvent: EventRef?
    @State private var joinToken: TokenRef?
    /// "You're in! +1 FavCoin" — shown on the event screen after a join
    @State private var banner: String?

    struct EventRef: Identifiable { let id: String }
    struct TokenRef: Identifiable { let id: String }

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(theme)
                if store.events.isEmpty && store.hasLoaded {
                    Text("No events yet. Start one, send the link to your group chat, and everyone who joins sees the same photos.")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                }
                ForEach(store.events) { event in
                    Button { openEvent = EventRef(id: event.id) } label: { row(event, theme: theme) }
                        .buttonStyle(.plain)
                }
                if let error = store.loadError, store.events.isEmpty {
                    Text(error).font(.system(size: 13)).foregroundStyle(theme.warning)
                }
            }
            .padding(16)
        }
        .refreshable { await store.refresh(context, force: true) }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await store.refresh(context) }
        .task { await openLaunched() }
        .sheet(isPresented: $creating) {
            EventCreateSheet(context: context) { event in
                store.upsert(event)
                banner = nil
                openAfterSheetCloses(event.id)
            }
        }
        .sheet(item: $joinToken) { token in
            EventJoinSheet(context: context, token: token.id) { event, coinCredited in
                store.upsert(event)
                banner = coinCredited == nil ? nil : EventCopy.joinedMessage(name: event.name, coinCredited: coinCredited ?? false)
                openAfterSheetCloses(event.id)
            }
        }
        .fullScreenCoverOrSheet(item: $openEvent) { ref in
            EventDetailView(context: context, eventId: ref.id, banner: banner, onGone: {
                store.remove(ref.id)
                openEvent = nil
            }, onChange: { store.upsert($0) })
        }
    }

    private func hero(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🚌🎉📸").font(.system(size: 34))
            Text("Photos only your group sees")
                .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Start an event, drop the link in the group text, and everyone who joins shares one album and the places you went. +1 FavCoin for joining.")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Button { creating = true } label: {
                Label("Start an event", systemImage: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                    .foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.24, blue: 0.5), context.accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func row(_ event: EventSummary, theme: WidgetTheme) -> some View {
        HStack(spacing: 12) {
            Text(event.emoji).font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Circle().fill(context.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                Text("\(EventCopy.memberCount(event.members.count)) · \(event.photoCount) photos · \(event.placeCount) places")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                if event.isHost {
                    Text("You're the coordinator").font(.system(size: 12, weight: .medium)).foregroundStyle(context.accent)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
    }

    /// Presenting the event while the sheet is still animating away made it
    /// flash and close (the 0.23.3 bug class) — wait for the page to settle.
    private func openAfterSheetCloses(_ id: String) {
        Task { @MainActor in
            await context.waitForPageToSettle()
            openEvent = EventRef(id: id)
        }
    }

    /// A link/invite (join screen) or a push (open the event).
    private func openLaunched() async {
        if let token = context.launchEventToken {
            context.launchEventToken = nil
            await context.waitForPageToSettle()
            joinToken = TokenRef(id: token)
        } else if let id = context.launchEventId {
            context.launchEventId = nil
            banner = nil
            await context.waitForPageToSettle()
            openEvent = EventRef(id: id)
        }
    }
}

extension View {
    /// Full-screen on iOS (the event is a whole screen); a sheet on the Mac.
    @ViewBuilder
    func fullScreenCoverOrSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

/// Name it (a Party Bus, a trip, a night out) and pick an emoji.
struct EventCreateSheet: View {
    let context: WidgetContext
    let onCreated: (EventSummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🎉"
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "New event", theme: theme,
                    confirm: (label: busy ? "Creating…" : "Create", enabled: !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty, action: create),
                    cancelDisabled: busy) {
            VStack(alignment: .leading, spacing: 18) {
                Text(emoji).font(.system(size: 64)).frame(maxWidth: .infinity)
                WidgetUI.textField("Event name (Party Bus, Beach weekend…)", text: $name, theme: theme)
                Text("Pick an emoji").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(EventCopy.emojiChoices, id: \.self) { e in
                        Button { emoji = e } label: {
                            Text(e).font(.system(size: 30)).frame(width: 52, height: 52)
                                .background(Circle().fill(e == emoji ? context.accent.opacity(0.25) : theme.secondaryBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Next you'll get a link to drop in your group text. Anyone with it can join; you can remove people or close joining any time.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                Spacer()
            }
            .padding(16)
        }
    }

    private func create() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let event = try await EventsClient(context: context).create(name: name, emoji: emoji)
                context.host.haptic(.success)
                context.track("event_created")
                dismiss()
                onCreated(event)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't create the event", message: "Check your connection and try again."))
            }
        }
    }
}

/// Where a link or invite lands: what the event is, and one big Join.
struct EventJoinSheet: View {
    let context: WidgetContext
    let token: String
    /// The event, and whether a FavCoin came with it (nil = already a member)
    let onJoined: (EventSummary, Bool?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: EventInvitePreview?
    @State private var failed: String?
    @State private var busy = false
    @State private var celebrate = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                if let preview {
                    Text(preview.emoji).font(.system(size: 96))
                        .scaleEffect(celebrate ? 1.25 : 1).rotationEffect(.degrees(celebrate ? 8 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.45), value: celebrate)
                    Text(preview.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
                    Text("\(preview.hostName) invited you · \(EventCopy.memberCount(preview.memberCount))")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                    if preview.alreadyMember {
                        WidgetUI.primaryButton("You're in, open it", color: context.accent) { openExisting(preview) }
                    } else if !preview.joinOpen {
                        Text("Joining is closed for this event.").font(.system(size: 15)).foregroundStyle(theme.warning)
                    } else {
                        WidgetUI.primaryButton(busy ? "Joining…" : EventCopy.joinButton(preview), color: context.accent) { join() }
                            .disabled(busy)
                        Text("Share photos with everyone there and save the places you go. +1 FavCoin 🌵 for joining.")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
                    }
                } else if let failed {
                    Text(failed).font(.system(size: 16)).foregroundStyle(theme.label).multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .padding(24)
            .background(theme.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            do { preview = try await EventsClient(context: context).preview(token: token) }
            catch { failed = "That invite link isn't valid anymore. Ask for a fresh one." }
        }
    }

    private func join() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await EventsClient(context: context).join(token: token)
                celebrate = true
                context.host.haptic(.success)
                context.track("event_joined", ["coin": result.coinCredited ? "1" : "0"])
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
                onJoined(result.event, result.coinCredited)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't join", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func openExisting(_ preview: EventInvitePreview) {
        Task { @MainActor in
            if let event = try? await EventsClient(context: context).detail(preview.id).event {
                dismiss()
                onJoined(event, nil)
            }
        }
    }
}

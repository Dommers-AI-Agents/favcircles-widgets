import SwiftUI
import PhotosUI
import FavWidgetsCore

/// The event's photo challenges as chips above the album: tap one to snap
/// or pick a photo for it (a FavCoin the first time). Done ones get a check.
struct EventChallengesStrip: View {
    let context: WidgetContext
    let event: EventSummary
    let photos: [EventPhoto]
    let onPick: (EventChallenge) -> Void
    let onAdd: () -> Void

    var body: some View {
        let theme = context.theme
        let done = EventTogether.doneChallengeIds(photos: photos, userId: context.host.currentUserId ?? "")
        let list = event.challengeList
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(list.isEmpty ? "Photo challenges" : "Photo challenges · \(done.intersection(list.map(\.id)).count) of \(list.count) done")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                Spacer()
                if event.isHost && !event.hasEnded {
                    Button(list.isEmpty ? "Add some" : "Add", action: onAdd).font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                }
            }
            if list.isEmpty {
                if event.isHost && !event.hasEnded {
                    Text("Give the group something to shoot for — a group selfie, the best dance move. Each one done earns a FavCoin 🌵.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list) { challenge in
                            let isDone = done.contains(challenge.id)
                            Button { onPick(challenge) } label: {
                                HStack(spacing: 6) {
                                    Text(challenge.emoji)
                                    Text(challenge.text).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    if isDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }
                                .foregroundStyle(theme.label)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(isDone ? Color.green.opacity(0.15) : theme.secondaryBackground))
                                .overlay(Capsule().stroke(isDone ? Color.green.opacity(0.5) : context.accent.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(event.hasEnded)
                        }
                    }
                }
            }
        }
    }
}

/// The coordinator picks challenges: suggestions, or their own.
struct EventAddChallengesSheet: View {
    let context: WidgetContext
    let event: EventSummary
    let onSaved: ([EventChallenge]) -> Void
    @State private var picked: Set<String> = []
    @State private var custom = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        let existing = Set(event.challengeList.map { $0.text.lowercased() })
        let suggestions = EventTogether.suggestedChallenges.filter { !existing.contains($0.text.lowercased()) }
        WidgetSheet(title: "Photo challenges", theme: theme,
                    confirm: (label: saving ? "Adding…" : "Add", enabled: !saving && (!picked.isEmpty || !custom.trimmingCharacters(in: .whitespaces).isEmpty), action: save)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Everyone sees them above the album. Each one someone completes earns them a FavCoin 🌵.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.textField("Your own (e.g. Photo with the bride)", text: $custom, theme: theme, height: 44)
                    ForEach(suggestions, id: \.text) { s in
                        Button {
                            if picked.contains(s.text) { picked.remove(s.text) } else { picked.insert(s.text) }
                        } label: {
                            HStack {
                                Text(s.emoji); Text(s.text).foregroundStyle(theme.label)
                                Spacer()
                                Image(systemName: picked.contains(s.text) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked.contains(s.text) ? context.accent : theme.secondaryLabel)
                            }
                            .font(.system(size: 16)).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    private func save() {
        var list = EventTogether.suggestedChallenges.filter { picked.contains($0.text) }
        let mine = custom.trimmingCharacters(in: .whitespaces)
        if !mine.isEmpty { list.insert(("📸", mine), at: 0) }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                let all = try await EventsClient(context: context).addChallenges(event.id, list)
                context.host.haptic(.success)
                context.track("event_challenges_added", ["count": "\(list.count)"])
                onSaved(all)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add them", message: "Check your connection and try again."))
            }
        }
    }
}

/// "Roll call · 5 of 8 here": I'm here (optionally with your spot, shown
/// only to the event and cleared when it ends); the coordinator pings the
/// rest or closes it.
struct EventRollCallBanner: View {
    let context: WidgetContext
    let event: EventSummary
    let rollCall: EventRollCall
    let onUpdate: (EventSummary?) -> Void
    @State private var shareSpot = false
    @State private var busy = false

    private var client: EventsClient { EventsClient(context: context) }

    var body: some View {
        let theme = context.theme
        let missing = EventTogether.missing(rollCall, members: event.members)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Roll call", systemImage: "hand.raised.fill").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                Spacer()
                Text(EventTogether.rollCallLine(rollCall, memberCount: event.members.count))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            if !missing.isEmpty {
                Text("Not yet: " + missing.map(\.name).joined(separator: ", "))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
            }
            if !rollCall.imHere {
                Toggle(isOn: $shareSpot) {
                    Text("Share where I am with the group").font(.system(size: 13)).foregroundStyle(.white)
                }
                .tint(.white)
                Button { answer() } label: {
                    Text("I'm here 🙋").font(.system(size: 17, weight: .heavy)).foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain).disabled(busy)
            }
            if event.isHost {
                HStack(spacing: 10) {
                    if !missing.isEmpty {
                        Button { ping() } label: {
                            Text("Ping the rest (\(missing.count))").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().stroke(.white, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { close() } label: {
                        Text("Done").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().stroke(.white, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !rollCall.locations.isEmpty {
                Text("📍 " + rollCall.locations.compactMap { spot in event.members.first { $0.id == spot.userId }?.name }.joined(separator: ", ") + " shared where they are")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.gradient))
    }

    private func answer() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let spot = shareSpot ? await context.host.currentLocation() : nil
            if let updated = try? await client.answerRollCall(event.id, spot: spot) {
                context.host.haptic(.success)
                context.track("event_rollcall_here", ["spot": spot == nil ? "0" : "1"])
                onUpdate(updated)
            }
        }
    }

    private func ping() {
        Task { @MainActor in
            if let n = try? await client.pingMissing(event.id) {
                context.host.haptic(.success)
                context.host.presentAlert(WidgetAlert(title: n == 0 ? "Already pinged" : "Pinged \(n)",
                                                      message: n == 0 ? "Give them a few minutes before pinging again." : "They got a \"Where are you?\" notification."))
            }
        }
    }

    private func close() {
        Task { @MainActor in
            if (try? await client.closeRollCall(event.id)) != nil { onUpdate(nil) }
        }
    }
}

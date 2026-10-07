import SwiftUI
import FavWidgetsCore

/// How an answer row shows family support.
enum CareSupportMode {
    case none
    /// The family (owner or watcher): react, and respond to a heads-up
    case family(store: CareStore)
    /// The person being checked on: who reacted, who's calling or coming
    case parent
}

/// Under an answer, for the family: four one-tap reactions and, on a
/// heads-up, "I'll call / I'm on my way / Got it" plus who already has it.
struct CareFamilySupportBar: View {
    let context: WidgetContext
    let ask: CareAsk
    @ObservedObject var store: CareStore
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        let myId = context.host.currentUserId
        let mine = ask.reactions.first { $0.userId == myId }?.kind
        VStack(alignment: .leading, spacing: 6) {
            if ask.alert {
                let lines = CareSupportCopy.familyLines(ask.responses, myId: myId)
                if !lines.isEmpty {
                    Text(lines.joined(separator: " · ")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                }
                HStack(spacing: 6) {
                    ForEach(CareSupportCopy.responses, id: \.key) { choice in
                        let picked = ask.responses.contains { $0.userId == myId && $0.action == choice.key }
                        Button { respond(choice.key) } label: {
                            Text("\(choice.emoji) \(choice.label)").font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(Capsule().fill(picked ? theme.warning : theme.tertiaryBackground))
                                .foregroundStyle(picked ? .white : theme.label)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(CareSupportCopy.reactions, id: \.key) { choice in
                    Button { react(mine == choice.key ? nil : choice.key) } label: {
                        Text(choice.emoji).font(.system(size: 17))
                            .frame(width: 34, height: 30)
                            .background(Capsule().fill(mine == choice.key ? context.accent.opacity(0.25) : theme.tertiaryBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityLabel(choice.label)
                    .accessibilityAddTraits(mine == choice.key ? .isSelected : [])
                }
                if let summary = CareSupportCopy.reactionSummary(ask.reactions) {
                    Text(summary).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
            }
        }
    }

    private func react(_ kind: String?) {
        busy = true
        context.host.haptic(.light)
        Task { @MainActor in
            defer { busy = false }
            if let updated = try? await CareAPI.react(context: context, askId: ask.askId, kind: kind) {
                store.replaceAsk(updated)
                context.track("care_reacted", ["kind": kind ?? "removed"])
            }
        }
    }

    private func respond(_ action: String) {
        busy = true
        context.host.haptic(.medium)
        Task { @MainActor in
            defer { busy = false }
            if let updated = try? await CareAPI.respondToAlert(context: context, askId: ask.askId, action: action) {
                store.replaceAsk(updated)
                context.track("care_alert_responded", ["action": action])
            }
        }
    }
}

/// Under an answer, for the parent: big and plain. "❤️ Wes · 💪 Sal",
/// "Wes is going to call you soon".
struct CareParentSupportLines: View {
    let context: WidgetContext
    let ask: CareAsk

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 3) {
            ForEach(CareSupportCopy.parentLines(ask.responses), id: \.self) { line in
                Label(line, systemImage: "phone.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.green)
            }
            if let summary = CareSupportCopy.reactionSummary(ask.reactions) {
                Text(summary).font(.system(size: 16)).foregroundStyle(theme.label)
            }
        }
    }
}

/// The parent's switch: pushes when family reacts (they still see them here).
struct CareReactionPushesToggle: View {
    let context: WidgetContext
    let plan: CarePlan
    @State private var on: Bool

    init(context: WidgetContext, plan: CarePlan) {
        self.context = context
        self.plan = plan
        _on = State(initialValue: !plan.reactionPushesOff)
    }

    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { value in
            on = value
            Task { try? await CareAPI.setReactionPushes(context: context, planId: plan.planId, on: value) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tell me when family sends love").font(.system(size: 15)).foregroundStyle(context.theme.label)
                Text("You'll always see it here either way.").font(.system(size: 12)).foregroundStyle(context.theme.secondaryLabel)
            }
        }
        .tint(context.accent)
    }
}

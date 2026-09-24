import SwiftUI
import FavWidgetsCore

/// Both roles on one screen: invitations and today's question for the
/// person being asked at the top, then the people this person checks on.
struct CareCheckinFullView: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore

    @State private var busy: String?
    @State private var note = ""
    @State private var showPicker = false
    @State private var detailPlan: CarePlan?
    @State private var profilePlan: CarePlan?

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plans = store.plans {
                    if plans.isEmpty { explainer }
                    ForEach(plans.invitations) { invitation(plan: $0) }
                    // Siblings waiting on this parent to let them in.
                    ForEach(plans.asParent.flatMap { plan in plan.pendingWatchers.map { (plan, $0) } }, id: \.1.id) {
                        watcherRequest(plan: $0.0, watcher: $0.1)
                    }
                    ForEach(plans.asParent.filter { !$0.isInvited && $0.status != "declined" }) { askedSection(plan: $0) }
                    ownedSection(plans.following)
                } else if let error = store.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.system(size: 14)).foregroundStyle(theme.danger)
                        Button("Try again") { Task { await store.load(context: context) } }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading…").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel) }
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await store.loadIfNeeded(context: context) }
        .refreshable { await store.load(context: context) }
        // Right after "check on Mom": the questionnaire that decides which
        // questions she gets, before the invitation is even answered. Opened
        // from the picker's onDismiss — a sheet presented while another is
        // still going away is dropped by SwiftUI.
        .sheet(isPresented: $showPicker, onDismiss: offerProfileIfJustCreated) { CareInvitePicker(context: context, store: store) }
        .sheet(item: $detailPlan) { plan in CarePlanDetailView(context: context, store: store, planId: plan.planId) }
        .sheet(item: $profilePlan) { plan in CareProfileSheet(context: context, store: store, plan: plan) }
    }

    private func offerProfileIfJustCreated() {
        guard let planId = store.profilePromptPlanId else { return }
        store.profilePromptPlanId = nil
        guard let plan = store.plans?.asOwner.first(where: { $0.planId == planId }) else { return }
        profilePlan = plan
    }

    // MARK: - Explainer

    private var explainer: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            Text("A short \"how are you?\" lands on your parent's phone a few times a day. They answer with one tap, without unlocking. You see every answer, and you hear about it when there's silence.")
                .font(.system(size: 15)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            Text("They need Circles on their phone with notifications on, and you need to be connected.")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent.opacity(0.10)))
    }

    // MARK: - Parent side

    private func invitation(plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Invitation", theme: theme)
            Text("\(plan.ownerName) would like to check in on you")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
            Text("You'd get a short question at \(CareCopy.timesLine(plan.times)). Answer with one tap from the Lock Screen. \(plan.ownerName) sees your answers, and hears if you haven't answered for a few hours.")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                WidgetUI.primaryButton(busy == "accept" ? "…" : "Yes, please", color: context.accent) {
                    run("accept") { try await CareAPI.respond(context: context, planId: plan.planId, accept: true) }
                }
                Button("No thanks") {
                    run("decline") { try await CareAPI.respond(context: context, planId: plan.planId, accept: false) }
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                .frame(width: 100)
            }
            .disabled(busy != nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    /// The parent decides who joins. Agreeing to one child seeing how you are
    /// is not agreeing to the whole family, so this is asked each time rather
    /// than left to whoever set the check-in up.
    private func watcherRequest(plan: CarePlan, watcher: CareWatcher) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Someone else wants to join", theme: theme)
            Text("\(watcher.name) would like to see your check-ins too")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
            Text("They'd see the same answers as \(plan.ownerName), and hear if you haven't answered. You won't get any extra questions.")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                WidgetUI.primaryButton(busy == "w-yes-\(watcher.userId)" ? "…" : "Yes, that's fine", color: context.accent) {
                    run("w-yes-\(watcher.userId)") {
                        try await CareAPI.respondToWatcher(context: context, planId: plan.planId, watcherId: watcher.userId, accept: true)
                    }
                }
                Button("No thanks") {
                    run("w-no-\(watcher.userId)") {
                        try await CareAPI.respondToWatcher(context: context, planId: plan.planId, watcherId: watcher.userId, accept: false)
                    }
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                .frame(width: 100)
            }
            .disabled(busy != nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    /// Who else is on this check-in, shown on the child's side so it is obvious
    /// the parent is asked once and the family shares one arrangement.
    @ViewBuilder
    private func familyRow(plan: CarePlan) -> some View {
        let theme = context.theme
        if !plan.watchers.isEmpty || plan.isOwner {
            VStack(alignment: .leading, spacing: 6) {
                if !plan.activeWatchers.isEmpty {
                    Text("Also watching: " + plan.activeWatchers.map(\.name).joined(separator: ", "))
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                ForEach(plan.pendingWatchers) { w in
                    Text("\(w.name) asked to join — waiting on \(plan.parentName)")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                if plan.isWatcher {
                    Text("\(plan.ownerName) set this up. You see the answers; they choose the times.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func askedSection(plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("From \(plan.ownerName)", theme: theme)
            if let ask = plan.openAsk {
                Text(ask.questionText)
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Asked at \(CareCopy.friendlyTime(ask.slot))").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                CareAnswerControls(context: context, ask: ask, disabled: busy != nil) { payload in
                    answerAsk(ask, payload: payload, plan: plan)
                }
                .id(ask.askId)
                TextField("Add a note (optional)", text: $note)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.tertiaryBackground))
            } else {
                Text(plan.isPaused ? "\(plan.ownerName) paused the questions for now." : "Nothing waiting. \(plan.ownerName) checks in at \(CareCopy.timesLine(plan.times)).")
                    .font(.system(size: 14)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
                if let last = plan.lastAnswer, let text = last.answerText, let at = last.answeredAt {
                    Text("Last answer: \(text) · \(CareCopy.relative(at, calendar: context.calendar))")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            Button("Stop these check-ins") {
                run("end-\(plan.planId)") {
                    try await CareAPI.endPlan(context: context, planId: plan.planId)
                    store.remove(planId: plan.planId)
                    return nil
                }
            }
            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    // MARK: - Owner side

    private func ownedSection(_ plans: [CarePlan]) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header(plans.isEmpty ? "Check on someone" : "People I check on", theme: theme)
            ForEach(plans) { plan in
                Button { detailPlan = plan } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(context.accent.opacity(0.15))
                            Text(String(plan.parentName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(context.accent)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(plan.parentName).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                                Text(CareCopy.statusChip(plan)).font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(plan.isActive ? .white : theme.secondaryLabel)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(plan.isActive ? context.accent : theme.tertiaryBackground))
                            }
                            familyRow(plan: plan)
                            Text(CareCopy.ownerLine(plan, calendar: context.calendar))
                                .font(.system(size: 12))
                                .foregroundStyle(plan.openAsk.flatMap(\.dueBy).map { $0 <= Date() } == true ? theme.warning : theme.secondaryLabel)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { showPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    Text(plans.isEmpty ? "Check on Mom or Dad" : "Check on someone else").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(context.accent)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func run(_ key: String, _ op: @escaping () async throws -> CarePlan?) {
        guard busy == nil else { return }
        busy = key
        Task {
            defer { busy = nil }
            do {
                if let plan = try await op() { store.apply(plan) }
                context.host.haptic(.success)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "How Are You?", message: error.localizedDescription))
            }
        }
    }

    private func answerAsk(_ ask: CareAsk, payload: CareAnswerPayload, plan: CarePlan) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.track("care_answer", ["kind": ask.kind.rawValue, "answer": payload.trackingValue])
        run("answer") {
            let answered = try await CareAPI.answer(context: context, askId: ask.askId, payload: payload, note: text)
            note = ""
            var updated = plan
            updated.openAsk = nil
            updated.lastAnswer = answered
            updated.lastAnsweredAt = answered.answeredAt
            return updated
        }
    }
}


import SwiftUI
import FavWidgetsCore

/// One person this user checks on: how they're doing, the care profile that
/// shapes the questions, times, the rotation, this week's trends, history.
struct CarePlanDetailView: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore
    let planId: String
    @Environment(\.dismiss) private var dismiss

    @State private var newQuestion = ""
    @State private var newKind: CareQuestionKind = .yesno
    @State private var history: [CareAsk] = []
    @State private var busy = false
    @State private var showProfile = false
    @State private var showAllRotation = false

    private var plan: CarePlan? { store.plans?.asOwner.first { $0.planId == planId } }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                if let plan {
                    VStack(alignment: .leading, spacing: 22) {
                        statusBlock(plan)
                        if let line = CareCopy.needsUpdateLine(plan) { notice(line, symbol: "arrow.down.circle") }
                        profileBlock(plan)
                        weekBlock(plan)
                        timesBlock(plan)
                        rotationBlock(plan)
                        historyBlock(plan)
                        Button("Stop checking on \(plan.parentName)") {
                            perform {
                                try await CareAPI.endPlan(context: context, planId: plan.planId)
                                store.remove(planId: plan.planId)
                                dismiss()
                            }
                        }
                        .font(.system(size: 13)).foregroundStyle(theme.danger)
                    }
                    .padding(16)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(plan?.parentName ?? "Check-in")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { history = await store.history(context: context, planId: planId) }
            .sheet(isPresented: $showProfile) {
                if let plan { CareProfileSheet(context: context, store: store, plan: plan) }
            }
        }
    }

    // MARK: - Status

    private func statusBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            Text(CareCopy.ownerLine(plan, calendar: context.calendar))
                .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            if plan.isInvited {
                Text(CareCopy.invitedLine(plan, calendar: context.calendar))
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                Button("Send the invitation again") {
                    perform {
                        let sent = try await CareAPI.resendInvite(context: context, planId: plan.planId)
                        store.apply(sent.plan)
                        context.host.presentAlert(WidgetAlert(title: "How Are You?", message: CareCopy.resendResult(sent.plan, delivered: sent.delivered)))
                    }
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent).disabled(busy)
            } else if plan.isActive || plan.isPaused {
                Button(plan.isPaused ? "Resume questions" : "Pause questions") {
                    perform { store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, status: plan.isPaused ? "active" : "paused")) }
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent).disabled(busy)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private func notice(_ text: String, symbol: String) -> some View {
        let theme = context.theme
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.warning)
            Text(text).font(.system(size: 13)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.warning.opacity(0.12)))
    }

    // MARK: - Care profile

    /// The questionnaire's answers, or the nudge to do it. This is what makes
    /// the rotation fit the parent, so it sits above the times.
    private func profileBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("About \(plan.parentName)", theme: theme)
            if plan.hasProfile {
                Text(CareCopy.profileSummary(plan))
                    .font(.system(size: 14)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
                Button("Update") { showProfile = true }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
            } else {
                Text("A few yes/no answers — lives alone, takes medication, in PT — and the questions fit \(plan.parentName) instead of everyone.")
                    .font(.system(size: 14)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
                WidgetUI.primaryButton("Tell us about \(plan.parentName)", color: context.accent) { showProfile = true }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(plan.hasProfile ? theme.secondaryBackground : context.accent.opacity(0.10)))
    }

    // MARK: - This week

    /// Trends for the 0–10 questions, the heads-ups, and how many were answered.
    @ViewBuilder
    private func weekBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        let trends = CareCopy.scaleTrends(history)
        let alerts = CareCopy.recentAlerts(history)
        let rate = CareCopy.answerRate(history)
        if rate.asked > 0 || !trends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                WidgetUI.header("This week", theme: theme)
                Text("\(rate.answered) of \(rate.asked) answered").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                ForEach(trends, id: \.short) { trend in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trend.short).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
                            Text("latest \(trend.latest) · \(trend.count == 1 ? "one answer" : "avg \(trend.averageText) over \(trend.count)")")
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        scaleBar(trend.latest, warn: trend.alerts > 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                }
                ForEach(alerts) { ask in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ask.answerText ?? "") — \(ask.questionText)").font(.system(size: 13)).foregroundStyle(theme.label)
                            if let at = ask.answeredAt {
                                Text(CareCopy.relative(at, calendar: context.calendar)).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func scaleBar(_ value: Int, warn: Bool) -> some View {
        let theme = context.theme
        return HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < value ? (warn ? theme.warning : context.accent) : theme.tertiaryBackground)
                    .frame(width: 6, height: 14)
            }
        }
        .accessibilityLabel("\(value) out of 10")
    }

    // MARK: - Times

    private func timesBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Times · their local time", theme: theme)
            FlowChips(items: plan.times) { time in
                HStack(spacing: 4) {
                    Text(CareCopy.friendlyTime(time)).font(.system(size: 13, weight: .semibold))
                    if plan.times.count > 1 {
                        Button { setTimes(plan, plan.times.filter { $0 != time }) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(context.accent))
            }
            if plan.times.count < 5 {
                Menu {
                    ForEach(CareCopy.timeChoices.filter { !plan.times.contains($0) }, id: \.self) { t in
                        Button(CareCopy.friendlyTime(t)) { setTimes(plan, (plan.times + [t]).sorted()) }
                    }
                } label: {
                    Label("Add a time", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                }
            }
        }
    }

    // MARK: - Rotation

    /// Everything that can be asked: the bank questions the profile brought
    /// in (switch any off), plus the owner's own (with a kind).
    private func rotationBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        let all = plan.rotation
        let shown = showAllRotation || all.count <= 8 ? all : Array(all.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Questions in rotation · \(plan.activeRotation.count)", theme: theme)
            Text("One goes out at each time, the most overdue first. Weekly ones wait for their day; \"did you go to PT?\" lands Friday evening.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            ForEach(shown) { q in rotationRow(plan, q) }
            if shown.count < all.count {
                Button("Show all \(all.count)") { showAllRotation = true }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Write your own question", text: $newQuestion)
                        .font(.system(size: 14)).padding(.horizontal, 10).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        .onSubmit { addQuestion(plan) }
                    Button("Add") { addQuestion(plan) }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                        .disabled(newQuestion.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                Picker("Answered with", selection: $newKind) {
                    ForEach(CareQuestionKind.pickable, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .font(.system(size: 13))
                .tint(context.accent)
            }
        }
    }

    private func rotationRow(_ plan: CarePlan, _ q: CareQuestion) -> some View {
        let theme = context.theme
        return HStack(spacing: 10) {
            Image(systemName: q.kind.symbolName).font(.system(size: 14)).foregroundStyle(q.muted ? theme.secondaryLabel : context.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(q.text).font(.system(size: 14)).foregroundStyle(q.muted ? theme.secondaryLabel : theme.label)
                    .strikethrough(q.muted).fixedSize(horizontal: false, vertical: true)
                Text([q.cadence, q.kind.label, q.isCustom ? "yours" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            if q.isCustom {
                Button { setQuestions(plan, plan.questions.filter { $0.id != q.id }) } label: {
                    Image(systemName: "minus.circle").foregroundStyle(theme.secondaryLabel)
                }
                .buttonStyle(.plain)
            } else {
                Toggle("", isOn: Binding(get: { !q.muted }, set: { on in setMuted(plan, q.id, muted: !on) }))
                    .labelsHidden().tint(context.accent)
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
        .disabled(busy)
    }

    // MARK: - History

    private func historyBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Answers", theme: theme)
            if history.isEmpty {
                Text("Nothing asked yet.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(history) { ask in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: CareCopy.answerSymbol(ask))
                        .font(.system(size: 14))
                        .foregroundStyle(ask.alert ? theme.warning : (ask.isAnswered ? context.accent : theme.secondaryLabel)).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ask.questionText).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                        HStack(spacing: 8) {
                            Text(answerLine(ask)).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
                            if ask.kind == .scale, let score = ask.answerScore { scaleBar(score, warn: ask.alert) }
                        }
                        if !ask.note.isEmpty { Text("“\(ask.note)”").font(.system(size: 13)).foregroundStyle(theme.label) }
                        Text(CareCopy.relative(ask.askedAt, calendar: context.calendar)).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func answerLine(_ ask: CareAsk) -> String {
        if let text = ask.answerText { return text }
        if ask.isMissed { return ask.pushDelivered ? "No answer" : "Not delivered" }
        return "Waiting…"
    }

    // MARK: - Edits

    private func setTimes(_ plan: CarePlan, _ times: [String]) {
        perform { store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, times: times)) }
    }

    private func setQuestions(_ plan: CarePlan, _ questions: [CareQuestion]) {
        perform { store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, questions: questions)) }
    }

    private func setMuted(_ plan: CarePlan, _ id: String, muted: Bool) {
        var ids = Set(plan.mutedQuestionIds)
        if muted { ids.insert(id) } else { ids.remove(id) }
        perform { store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, mutedQuestionIds: Array(ids).sorted())) }
    }

    private func addQuestion(_ plan: CarePlan) {
        let text = newQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !plan.rotation.contains(where: { $0.text == text }) else { return }
        let kind = newKind
        newQuestion = ""
        context.track("care_question_added", ["kind": kind.rawValue])
        var draft = CareQuestion(id: "new_\(UUID().uuidString.prefix(8))", text: text, kind: kind)
        if kind == .scale { draft.low = "Not at all"; draft.high = "Very much" }
        setQuestions(plan, plan.questions + [draft])
    }

    private func perform(_ op: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await op(); context.host.haptic(.light) }
            catch { context.host.presentAlert(WidgetAlert(title: "How Are You?", message: error.localizedDescription)) }
        }
    }
}

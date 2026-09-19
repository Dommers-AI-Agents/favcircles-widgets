import SwiftUI
import FavWidgetsCore

/// One person this user checks on: times, questions, pause, history, end.
struct CarePlanDetailView: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore
    let planId: String
    @Environment(\.dismiss) private var dismiss

    @State private var newQuestion = ""
    @State private var history: [CareAsk] = []
    @State private var busy = false

    private var plan: CarePlan? { store.plans?.asOwner.first { $0.planId == planId } }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                if let plan {
                    VStack(alignment: .leading, spacing: 22) {
                        statusBlock(plan)
                        timesBlock(plan)
                        questionsBlock(plan)
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
        }
    }

    private func statusBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            Text(CareCopy.ownerLine(plan, calendar: context.calendar))
                .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            if plan.isInvited {
                Text("They'll see the invitation in their Circles app. Nothing is asked until they say yes.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
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

    private func questionsBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        let shown = plan.usesDefaultQuestions ? plan.defaultQuestions : plan.questions.map(\.text)
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header(plan.usesDefaultQuestions ? "Questions · rotating defaults" : "Your questions · rotating", theme: theme)
            ForEach(Array(shown.enumerated()), id: \.offset) { index, text in
                HStack(spacing: 8) {
                    Text(text).font(.system(size: 14)).foregroundStyle(plan.usesDefaultQuestions ? theme.secondaryLabel : theme.label)
                    Spacer()
                    if !plan.usesDefaultQuestions {
                        Button { setQuestions(plan, shown.enumerated().filter { $0.offset != index }.map(\.element)) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(theme.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
            }
            HStack(spacing: 8) {
                TextField("Write your own question", text: $newQuestion)
                    .font(.system(size: 14)).padding(.horizontal, 10).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                    .onSubmit { addQuestion(plan) }
                Button("Add") { addQuestion(plan) }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    .disabled(newQuestion.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            Text(plan.usesDefaultQuestions ? "Add one of your own and only yours will be used, in order." : "Asked in this order, then around again.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private func historyBlock(_ plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Answers", theme: theme)
            if history.isEmpty {
                Text("Nothing asked yet.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(history) { ask in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: ask.answer?.symbolName ?? (ask.isMissed ? "moon.zzz" : "clock"))
                        .font(.system(size: 14)).foregroundStyle(ask.answer == nil ? theme.secondaryLabel : context.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ask.questionText).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                        Text(answerLine(ask)).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
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

    private func setTimes(_ plan: CarePlan, _ times: [String]) {
        perform { store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, times: times)) }
    }

    private func setQuestions(_ plan: CarePlan, _ questions: [String]) {
        perform { store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, questions: questions)) }
    }

    private func addQuestion(_ plan: CarePlan) {
        let q = newQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let base = plan.usesDefaultQuestions ? [] : plan.questions.map(\.text)
        newQuestion = ""
        setQuestions(plan, base + [q])
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

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

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plans = store.plans {
                    if plans.isEmpty { explainer }
                    ForEach(plans.invitations) { invitation(plan: $0) }
                    ForEach(plans.asParent.filter { !$0.isInvited && $0.status != "declined" }) { askedSection(plan: $0) }
                    ownedSection(plans.asOwner)
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
        .sheet(isPresented: $showPicker) { CareInvitePicker(context: context, store: store) }
        .sheet(item: $detailPlan) { plan in CarePlanDetailView(context: context, store: store, planId: plan.planId) }
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

    private func askedSection(plan: CarePlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("From \(plan.ownerName)", theme: theme)
            if let ask = plan.openAsk {
                Text(ask.questionText)
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Asked at \(CareCopy.friendlyTime(ask.slot))").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                VStack(spacing: 8) {
                    ForEach(CareAnswer.allCases, id: \.self) { answer in
                        Button {
                            answerAsk(ask, answer: answer, plan: plan)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: answer.symbolName).font(.system(size: 18, weight: .semibold))
                                Text(answer.label).font(.system(size: 18, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(answer == .great ? .white : theme.label)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(answer == .great ? context.accent : theme.tertiaryBackground))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy != nil)
                    }
                }
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

    private func answerAsk(_ ask: CareAsk, answer: CareAnswer, plan: CarePlan) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.track("care_answer", ["answer": answer.rawValue])
        run("answer") {
            let answered = try await CareAPI.answer(context: context, askId: ask.askId, answer: answer, note: text)
            note = ""
            var updated = plan
            updated.openAsk = nil
            updated.lastAnswer = answered
            updated.lastAnsweredAt = answered.answeredAt
            return updated
        }
    }
}

/// Pick a connection to check on. Creates the plan with the default times
/// and questions; the detail screen is where those get tuned.
struct CareInvitePicker: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [WidgetContact] = []
    @State private var loading = true
    @State private var error: String?
    @State private var creating: String?
    @State private var query = ""

    private var filtered: [WidgetContact] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let existing = Set((store.plans?.asOwner ?? []).map(\.parentId))
        return contacts.filter { !existing.contains($0.id) && (q.isEmpty || $0.displayName.lowercased().contains(q)) }
    }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("They'll get an invitation to say yes to. Questions start only after they accept.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                    TextField("Search your connections", text: $query)
                        .font(.system(size: 15)).padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    if loading {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading your connections…").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(theme.danger)
                    } else if filtered.isEmpty {
                        Text(contacts.isEmpty ? "Connect with your parent in Circles first, then come back here." : "No one matches.")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    ForEach(filtered) { contact in
                        Button { create(contact) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(context.accent.opacity(0.15))
                                    Text(String(contact.displayName.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold)).foregroundStyle(context.accent)
                                }
                                .frame(width: 36, height: 36)
                                Text(contact.displayName).font(.system(size: 15)).foregroundStyle(theme.label)
                                Spacer()
                                if creating == contact.id { ProgressView().controlSize(.small) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(creating != nil)
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Who to check on")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                do { contacts = try await context.host.fetchConnections().sorted { $0.displayName < $1.displayName } }
                catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }

    private func create(_ contact: WidgetContact) {
        creating = contact.id
        Task {
            defer { creating = nil }
            do {
                let plan = try await CareAPI.createPlan(context: context, parentId: contact.id, times: CareCopy.defaultTimes, questions: [])
                store.apply(plan)
                context.track("care_plan_created")
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't invite them", message: error.localizedDescription))
            }
        }
    }
}

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
            .task { history = (try? await CareAPI.asks(context: context, planId: planId)) ?? [] }
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

/// Chips that wrap onto new lines.
struct FlowChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // Simple: rows of up to three chips. Times are short, so this is enough.
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) { ForEach(row, id: \.self) { content($0) } }
            }
        }
    }
}

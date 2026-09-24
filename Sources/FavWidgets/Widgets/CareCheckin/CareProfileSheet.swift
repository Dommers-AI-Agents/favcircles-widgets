import SwiftUI
import FavWidgetsCore

/// The short questionnaire about the parent — lives alone, takes medication,
/// in PT, and so on. The answers decide which questions go into rotation
/// ("Did you go to PT this week?" only when there is PT). Owner-only; the
/// list of questions is the server's, so it can grow without a release.
struct CareProfileSheet: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore
    let plan: CarePlan
    @Environment(\.dismiss) private var dismiss

    @State private var answers: [String: Bool]
    @State private var saving = false

    init(context: WidgetContext, store: CareStore, plan: CarePlan) {
        self.context = context
        self.store = store
        self.plan = plan
        _answers = State(initialValue: plan.profile ?? [:])
    }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "About \(plan.parentName)", theme: theme,
                    confirm: (label: saving ? "Saving…" : "Save", enabled: !saving, action: save)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("A few quick yes/no answers so the questions fit \(plan.parentName). You can change these any time.")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                    ForEach(plan.profileFields) { field in
                        Toggle(isOn: Binding(
                            get: { answers[field.key] ?? false },
                            set: { answers[field.key] = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(field.question).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label)
                                if !field.hint.isEmpty {
                                    Text(field.hint).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(context.accent)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    }
                    if plan.profileFields.isEmpty {
                        Text("The questionnaire isn't available right now. Try again in a moment.")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .padding(16)
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        // Every field is sent, so an untouched toggle is an explicit "no" and
        // the plan counts as having a profile from now on.
        var full: [String: Bool] = [:]
        for field in plan.profileFields { full[field.key] = answers[field.key] ?? false }
        Task {
            defer { saving = false }
            do {
                store.apply(try await CareAPI.updatePlan(context: context, planId: plan.planId, profile: full))
                context.track("care_profile_saved", ["flags": String(full.values.filter { $0 }.count)])
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "How Are You?", message: error.localizedDescription))
            }
        }
    }
}

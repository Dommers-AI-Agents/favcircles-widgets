import SwiftUI
import FavWidgetsCore

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
    /// A plan someone else already made on this person, offered instead of a
    /// duplicate that would ask them twice.
    struct JoinOffer: Identifiable { let contact: WidgetContact; let message: String; var id: String { contact.id } }
    @State private var joinOffer: JoinOffer?
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
            .alert("Already being checked on", isPresented: Binding(
                get: { joinOffer != nil },
                set: { if !$0 { joinOffer = nil } }
            ), presenting: joinOffer) { offer in
                Button("Ask to join") { join(offer.contact) }
                Button("Not now", role: .cancel) { joinOffer = nil }
            } message: { offer in
                Text(offer.message)
            }
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
                // The full view picks this up and opens the "About Mom" questionnaire.
                store.profilePromptPlanId = plan.planId
            } catch let api as WidgetAPIError where api.code == "plan_exists" {
                // Someone in the family already set this up. A second plan
                // would ask the parent twice on two schedules, so offer to
                // join theirs instead of leaving a dead end.
                offerToJoin(contact, because: api.message)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't invite them", message: error.localizedDescription))
            }
        }
    }

    private func offerToJoin(_ contact: WidgetContact, because message: String) {
        joinOffer = JoinOffer(contact: contact, message: message)
    }

    private func join(_ contact: WidgetContact) {
        joinOffer = nil
        creating = contact.id
        Task {
            defer { creating = nil }
            do {
                let plan = try await CareAPI.requestToJoinForParent(context: context, parentId: contact.id)
                store.apply(plan)
                context.track("care_join_requested")
                context.host.haptic(.success)
                context.host.presentAlert(WidgetAlert(
                    title: "Asked to join",
                    message: "\(plan.parentName) decides who sees their check-ins. You'll hear once they answer."
                ))
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't ask to join", message: error.localizedDescription))
            }
        }
    }
}

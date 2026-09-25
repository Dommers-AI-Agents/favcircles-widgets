import SwiftUI
import FavWidgetsCore

/// The owner picks a family member to take part in a check-in. They get an
/// invitation to accept; once they do, the parent is told who joined.
struct CareFamilyPicker: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore
    let plan: CarePlan
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [WidgetContact] = []
    @State private var loading = true
    @State private var error: String?
    @State private var inviting: String?
    @State private var query = ""

    private var filtered: [WidgetContact] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let taken = Set([plan.parentId, plan.ownerId] + plan.watchers.map(\.userId))
        return contacts.filter { !taken.contains($0.id) && (q.isEmpty || $0.displayName.lowercased().contains(q)) }
    }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("They'll get an invitation to accept. Once they do, they see \(plan.parentName)'s answers and hear when a question goes unanswered — and \(plan.parentName) is told who joined.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                    TextField("Search your connections", text: $query)
                        .font(.system(size: 15)).padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    if loading {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading your connections…").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(theme.danger)
                    } else if filtered.isEmpty {
                        Text(contacts.isEmpty ? "Connect with them in Circles first, then come back here." : "No one else to invite.")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    ForEach(filtered) { contact in
                        Button { invite(contact) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(context.accent.opacity(0.15))
                                    Text(String(contact.displayName.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold)).foregroundStyle(context.accent)
                                }
                                .frame(width: 36, height: 36)
                                Text(contact.displayName).font(.system(size: 15)).foregroundStyle(theme.label)
                                Spacer()
                                if inviting == contact.id { ProgressView().controlSize(.small) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(inviting != nil)
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Invite family")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                do { contacts = try await context.host.fetchConnections().sorted { $0.displayName < $1.displayName } }
                catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }

    private func invite(_ contact: WidgetContact) {
        inviting = contact.id
        Task {
            defer { inviting = nil }
            do {
                let updated = try await CareAPI.requestToJoin(context: context, planId: plan.planId, watcherId: contact.id)
                store.apply(updated)
                context.track("care_family_invited")
                context.host.haptic(.success)
                context.host.presentAlert(WidgetAlert(
                    title: "Invitation sent",
                    message: CareCopy.familyInviteResult(contact.displayName, parentName: plan.parentName, delivered: true)
                ))
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't invite them", message: error.localizedDescription))
            }
        }
    }
}

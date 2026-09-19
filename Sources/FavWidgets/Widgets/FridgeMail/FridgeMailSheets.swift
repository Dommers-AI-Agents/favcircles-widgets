import SwiftUI
import PhotosUI
import FavWidgetsCore

/// After a photo is picked: see it on the card, name the child, write the
/// note, add it to the queue. The print file is rendered and uploaded here
/// so the weekly run has nothing to do but hand a URL to the printer.
struct FridgeMailAddSheet: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore
    let image: PostcardPlatformImage
    @Environment(\.dismiss) private var dismiss

    @State private var childName = ""
    @State private var ageText = ""
    @State private var note = ""
    @State private var isSaving = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FridgeMailCanvasView(image: image, childName: childName, size: CGSize(width: 330, height: 220))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
                        .frame(maxWidth: .infinity)
                    if PostcardRendering.isSoftForPrint(image) {
                        Label("This photo is small and may print soft.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(theme.warning)
                    }
                    WidgetUI.header("On the back", theme: theme)
                    HStack(spacing: 8) {
                        WidgetUI.textField("Child's name", text: $childName, theme: theme)
                        WidgetUI.textField("Age", text: $ageText, theme: theme).frame(width: 80)
                    }
                    TextField("A note for the fridge (optional)", text: $note, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(2...4)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        .onChange(of: note) { value in
                            if value.count > FridgeMailCopy.noteMaxChars { note = String(value.prefix(FridgeMailCopy.noteMaxChars)) }
                        }
                    Text(FridgeMailCopy.backHeadline(childName: childName, ageText: ageText, date: Date(), calendar: context.calendar)
                         + "\n" + FridgeMailCopy.signature(familyName: store.plan?.familyName ?? ""))
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.primaryButton(isSaving ? "Adding…" : "Add to the queue", color: context.accent) { save() }
                        .disabled(isSaving)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("New card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let jpeg = try FridgeMailRendering.printJPEG(image: image, childName: childName.trimmingCharacters(in: .whitespaces))
                let url = try await context.host.uploadPrintImage(jpeg)
                let plan = try await FridgeMailAPI.enqueue(
                    context: context, imageURL: url,
                    childName: childName.trimmingCharacters(in: .whitespaces),
                    ageText: ageText.trimmingCharacters(in: .whitespaces),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                store.apply(plan)
                context.track("fridgemail_enqueued")
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add it", message: error.localizedDescription))
            }
        }
    }
}

/// Name, relation and a US address. The server checks the address with
/// USPS before it's saved, so a typo is caught here and not at the printer.
struct FridgeMailRecipientSheet: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relation = "Grandma"
    @State private var address = PostcardMailAddress()
    @State private var isSaving = false

    private static let relations = ["Grandma", "Grandpa", "Nana", "Papa", "Aunt", "Uncle", ""]

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(Self.relations, id: \.self) { r in
                                Button(r.isEmpty ? "Just the name" : r) { relation = r }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(relation.isEmpty ? "Relation" : relation)
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 15)).foregroundStyle(theme.label)
                            .frame(width: 110, height: 38)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        }
                        WidgetUI.textField("Name", text: $name, theme: theme, content: .name)
                    }
                    Text("Printed on the card as \"\(relation.isEmpty ? name : "\(relation) \(name)")\".")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.header("Address", theme: theme)
                    WidgetUI.textField("Street address", text: $address.line1, theme: theme, content: .streetAddressLine1)
                    WidgetUI.textField("Apt, suite (optional)", text: $address.line2, theme: theme, content: .streetAddressLine2)
                    HStack(spacing: 8) {
                        WidgetUI.textField("City", text: $address.city, theme: theme, content: .addressCity)
                        Menu {
                            ForEach(PostcardMailAddress.states, id: \.self) { code in Button(code) { address.state = code } }
                        } label: {
                            HStack(spacing: 4) {
                                Text(address.state.isEmpty ? "State" : address.state)
                                    .foregroundStyle(address.state.isEmpty ? theme.secondaryLabel : theme.label)
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            }
                            .font(.system(size: 15))
                            .frame(width: 78, height: 38)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        }
                    }
                    WidgetUI.textField("ZIP", text: $address.zip, theme: theme, content: .postalCode, numeric: true, capitalizeAll: true)
                    Text("US addresses only for now. We check it with USPS before saving.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.primaryButton(isSaving ? "Checking the address…" : "Add", color: context.accent) { save() }
                        .disabled(isSaving || !canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Add a grandparent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
        }
    }

    private var canSave: Bool {
        var a = address
        a.name = name
        return a.isComplete
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let plan = try await FridgeMailAPI.addRecipient(
                    context: context, name: name.trimmingCharacters(in: .whitespaces), relation: relation, address: address)
                store.apply(plan)
                context.track("fridgemail_recipient_added")
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add them", message: error.localizedDescription))
            }
        }
    }
}

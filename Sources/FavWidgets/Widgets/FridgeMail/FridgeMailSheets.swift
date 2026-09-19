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
/// Add a grandparent, or change one. The address is checked with the postal
/// service as it's typed (the same form the postcard uses); a correction is
/// shown and must be accepted before anything is saved, and a grandparent's
/// name or address can be changed without removing and re-adding them.
struct FridgeMailRecipientSheet: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore
    /// Set when changing someone who is already on the list.
    var editing: FridgeMailRecipient? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relation = "Grandma"
    @State private var address = PostcardMailAddress()
    @State private var quote: PostcardMail.Quote?
    @State private var quoteError: String?
    @State private var isQuoting = false
    @State private var quoteTask: Task<Void, Never>?
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
                    MailAddressForm(theme: theme, accent: context.accent, address: $address, quote: quote, quoteError: quoteError,
                                    isQuoting: isQuoting, showsName: false,
                                    onAddressSettled: scheduleQuote, onAcceptCorrection: acceptCorrection)
                    Text("US addresses only for now.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.primaryButton(saveTitle, color: context.accent) { save() }
                        .disabled(isSaving || !canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(editing == nil ? "Add a grandparent" : "Edit \(editing?.displayName ?? "")")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
            .onAppear(perform: prefill)
        }
    }

    private var saveTitle: String {
        if isSaving { return "Saving…" }
        if isQuoting { return "Checking the address…" }
        return editing == nil ? "Add" : "Save"
    }

    /// Everything filled in, and the postal service agreed with it (or the
    /// person accepted the correction). Never saves an address they haven't
    /// seen confirmed.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && addressWithName.isComplete
            && MailAddressForm.isSettled(addressWithName, quote: quote)
    }

    private var addressWithName: PostcardMailAddress {
        var a = address
        a.name = name.trimmingCharacters(in: .whitespaces)
        return a
    }

    private func prefill() {
        guard let editing, address.line1.isEmpty else { return }
        name = editing.name
        relation = editing.relation
        address = editing.address
        address.name = editing.name
        scheduleQuote()
    }

    /// Re-checks the address a beat after typing stops. The check is metered
    /// on the vendor's side, so it runs once per settled address rather than
    /// once per keystroke.
    private func scheduleQuote() {
        quoteTask?.cancel()
        quote = nil
        quoteError = nil
        var probe = address
        probe.name = name.isEmpty ? "Recipient" : name
        guard probe.isComplete else { return }
        quoteTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            isQuoting = true
            defer { isQuoting = false }
            do {
                let result = try await PostcardMail.quote(context: context, address: probe)
                guard !Task.isCancelled else { return }
                quote = result
            } catch {
                guard !Task.isCancelled else { return }
                quoteError = error.localizedDescription
            }
        }
    }

    /// Accepting the correction writes it into the form; the re-check comes
    /// back matching and the fields show what will actually print.
    private func acceptCorrection() {
        guard let quote else { return }
        var corrected = quote.address
        corrected.name = address.name
        address = corrected
    }

    private func save() {
        guard !isSaving, canSave else { return }
        isSaving = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        Task {
            defer { isSaving = false }
            do {
                let plan: FridgeMailPlan
                if let editing {
                    plan = try await FridgeMailAPI.updateRecipient(context: context, id: editing.id, name: trimmed, relation: relation, address: address)
                    context.track("fridgemail_recipient_edited")
                } else {
                    plan = try await FridgeMailAPI.addRecipient(context: context, name: trimmed, relation: relation, address: address)
                    context.track("fridgemail_recipient_added")
                }
                store.apply(plan)
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: editing == nil ? "Couldn't add them" : "Couldn't save that", message: error.localizedDescription))
            }
        }
    }
}

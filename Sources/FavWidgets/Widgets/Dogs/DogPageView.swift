import SwiftUI
import PhotosUI
import FavWidgetsCore

/// One dog's page: the profile, then the private records (vaccines, vet
/// visits, medications, weight, the vet, insurance) and the vet's paperwork
/// as Documents. Paperwork is kept as the photos or PDF itself, never read by
/// a paid model (Wes, 2026-10-23: "Having the image alone is sufficient").
struct DogPageView: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    @ObservedObject var state: WidgetStateController<DogsState>
    let dogId: String
    let onClose: () -> Void
    @State private var editingProfile = false
    @State private var editing: DogRecordEdit?
    @State private var removing = false
    @State private var viewingPhoto: LocalPhoto?

    struct LocalPhoto: Identifiable { let id: String }

    private var dog: DogProfile? { store.me.dogs.first { $0.id == dogId } }
    private var records: DogRecords { state.model.records(for: dogId) }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                if let dog {
                    VStack(alignment: .leading, spacing: 16) {
                        header(dog, theme: theme)
                        // The paperwork first (Wes, 2026-10-23)
                        DogDocumentsPanel(context: context, state: state, dogId: dogId, dogName: dog.name)
                        vaccines(theme)
                        visits(theme)
                        medications(theme)
                        weights(theme)
                        vet(theme)
                        insurance(theme)
                        Button(role: .destructive) { removing = true } label: {
                            Text("Remove \(dog.name)").font(.system(size: 14)).foregroundStyle(theme.danger).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(16)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(dog?.name ?? "")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) }
                ToolbarItem(placement: .primaryAction) {
                    Button { if let dog { share(dog) } } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .sheet(isPresented: $editingProfile) {
            if let dog { DogEditSheet(context: context, dog: dog) { store.upsertDog($0) } }
        }
        .sheet(item: $editing) { edit in
            DogRecordEditor(context: context, edit: edit, records: records) { updated in
                state.update { $0.records[dogId] = updated }
            }
        }
        .sheet(item: $viewingPhoto) { photo in
            DogLocalPhotoViewer(context: context, name: photo.id) {
                state.update { s in
                    var r = s.records(for: dogId)
                    if r.insurance.cardPhoto == photo.id { r.insurance.cardPhoto = nil }
                    s.records[dogId] = r
                }
                DogLocalPhotos.delete(photo.id)
            }
        }
        .confirmationDialog("Remove \(dog?.name ?? "this dog")?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their profile leaves the Dog Park. Their records stay saved here in case you add them back.")
        }
    }

    // MARK: Sections

    private func header(_ dog: DogProfile, theme: WidgetTheme) -> some View {
        VStack(spacing: 8) {
            DogAvatar(url: dog.photoURL, size: 120, accent: context.accent, theme: theme)
            Text(dog.name).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
            let sub = DogCopy.subtitle(dog, calendar: context.calendar)
            if !sub.isEmpty { Text(sub).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel) }
            if !dog.personality.isEmpty {
                Text("“\(dog.personality)”").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(theme.label)
            }
            Button("Edit profile") { editingProfile = true }.font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private func vaccines(_ theme: WidgetTheme) -> some View {
        section("Vaccines", theme: theme, add: { editing = .vaccine(nil) }) {
            if records.vaccines.isEmpty { emptyLine("Rabies, DHPP, Bordetella… add them for due-date reminders.") }
            ForEach(records.vaccines) { v in
                let status = DogVaccineStatus.of(v, calendar: context.calendar)
                row(title: v.name,
                    detail: [v.givenOn.flatMap { DogDay.display($0, calendar: context.calendar) }.map { "Given \($0)" },
                             v.dueOn.flatMap { DogDay.display($0, calendar: context.calendar) }.map { "due \($0)" }].compactMap { $0 }.joined(separator: " · "),
                    badge: status == .noDueDate ? nil : status.text,
                    badgeColor: status.needsAttention ? theme.warning : theme.success) { editing = .vaccine(v) }
            }
        }
    }

    private func visits(_ theme: WidgetTheme) -> some View {
        section("Vet visits", theme: theme, add: { editing = .visit(nil) }) {
            if records.vetVisits.isEmpty { emptyLine("Checkups, sick visits, the time they ate a sock.") }
            ForEach(records.vetVisits) { v in
                row(title: v.reason.isEmpty ? "Visit" : v.reason,
                    detail: [v.date.flatMap { DogDay.display($0, calendar: context.calendar) }, v.clinic.isEmpty ? nil : v.clinic].compactMap { $0 }.joined(separator: " · ")) {
                    editing = .visit(v)
                }
            }
        }
    }

    private func medications(_ theme: WidgetTheme) -> some View {
        section("Medications", theme: theme, add: { editing = .medication(nil) }) {
            if records.medications.isEmpty { emptyLine("Heartworm, flea and tick, anything else.") }
            ForEach(records.medications) { m in
                row(title: [m.name, m.dose].filter { !$0.isEmpty }.joined(separator: " "), detail: m.schedule) { editing = .medication(m) }
            }
        }
    }

    private func weights(_ theme: WidgetTheme) -> some View {
        section("Weight", theme: theme, add: { editing = .weight(nil) }) {
            if records.weights.isEmpty { emptyLine("Track it over time.") }
            ForEach(records.weights.reversed()) { w in
                row(title: "\(w.lbs.formatted(.number.precision(.fractionLength(0...1)))) lb",
                    detail: DogDay.display(w.date, calendar: context.calendar) ?? w.date) { editing = .weight(w) }
            }
        }
    }

    private func vet(_ theme: WidgetTheme) -> some View {
        section("Vet", theme: theme, add: { editing = .vet }, addSymbol: "pencil.circle.fill") {
            if records.vet.isEmpty { emptyLine("Your vet's name and number, one tap away.") } else {
                VStack(alignment: .leading, spacing: 4) {
                    if !records.vet.clinic.isEmpty { Text(records.vet.clinic).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label) }
                    if !records.vet.address.isEmpty { Text(records.vet.address).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                    if !records.vet.phone.isEmpty { callButton(records.vet.phone, label: "Call the vet") }
                }
            }
        }
    }

    private func insurance(_ theme: WidgetTheme) -> some View {
        let ins = records.insurance
        return section("Insurance", theme: theme, add: { editing = .insurance }, addSymbol: "pencil.circle.fill") {
            if ins.isEmpty { emptyLine("Provider, policy number and the claims line. The card photo stays on this phone.") } else {
                VStack(alignment: .leading, spacing: 4) {
                    if !ins.provider.isEmpty { Text(ins.provider).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label) }
                    if !ins.policyNumber.isEmpty {
                        Text("Policy \(ins.policyNumber)").font(.system(size: 13, design: .monospaced)).foregroundStyle(theme.secondaryLabel)
                            .textSelection(.enabled)
                    }
                    if !ins.claimsPhone.isEmpty { callButton(ins.claimsPhone, label: "Call claims") }
                    if let card = ins.cardPhoto {
                        Button { viewingPhoto = LocalPhoto(id: card) } label: {
                            Label("Insurance card", systemImage: "creditcard").font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func section<C: View>(_ title: String, theme: WidgetTheme, add: @escaping () -> Void, addSymbol: String = "plus.circle.fill",
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header(title, theme: theme)
                Button(action: add) { Image(systemName: addSymbol).font(.system(size: 22)).foregroundStyle(context.accent) }
                    .buttonStyle(.plain)
            }
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(context.theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
    }

    private func row(title: String, detail: String, badge: String? = nil, badgeColor: Color = .clear, onTap: @escaping () -> Void) -> some View {
        let theme = context.theme
        return Button(action: onTap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel) }
                }
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(badgeColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.14)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func callButton(_ phone: String, label: String) -> some View {
        Button {
            let digits = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel://\(digits)") { context.host.openURL(url) }
        } label: {
            Label("\(label) · \(phone)", systemImage: "phone.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
        }
        .buttonStyle(.plain)
    }

    private func share(_ dog: DogProfile) {
        Task { @MainActor in
            let content = DogsWidget.shareCardContent(dog, image: await DogShareImages.jpeg(dog.photoURL))
            context.track("dog_profile_shared")
            context.host.share(WidgetShareKit.items(descriptor: context.descriptor, content: content))
        }
    }

    private func remove() {
        Task { @MainActor in
            do {
                try await DogsClient(context: context).deleteDog(dogId)
                store.removeDog(dogId)
                onClose()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't remove", message: DogErrors.message(error)))
            }
        }
    }
}

/// A certificate / card photo stored on this phone.
struct DogLocalThumb: View {
    let name: String
    let theme: WidgetTheme
    @State private var image: PostcardPlatformImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.tertiaryBackground)
            if let image { Image(postcardImage: image).resizable().scaledToFill() } else { Image(systemName: "doc.text.image") }
        }
        .frame(width: 84, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task { if let data = DogLocalPhotos.load(name) { image = PostcardPlatformImage(data: data) } }
    }
}

/// Full view of a local photo, with Share (to send it to daycare) and Delete.
struct DogLocalPhotoViewer: View {
    let context: WidgetContext
    let name: String
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: PostcardPlatformImage?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image { Image(postcardImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { if let data = DogLocalPhotos.load(name) { context.host.share([.imageJPEG(data)]) } } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { confirming = true } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task { if let data = DogLocalPhotos.load(name) { image = PostcardPlatformImage(data: data) } }
        .confirmationDialog("Delete this photo?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

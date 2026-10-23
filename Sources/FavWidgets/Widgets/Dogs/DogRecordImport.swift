import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FavWidgetsCore

/// Import from your vet (Wes, 2026-10-22): there's no one system vets share,
/// so it reads the paperwork itself. Up to 4 photos of it, or the PDF the
/// vet emailed, go to the server, which has the model read them and keeps
/// nothing. The person checks every row (unsure ones are flagged) before
/// anything joins the private records. The paperwork itself can be kept in
/// the dog's Documents (on this phone), and when it can't be read it can
/// still be saved there (Wes, 2026-10-23).
struct DogRecordImportSheet: View {
    let context: WidgetContext
    let dogName: String?
    let existing: DogRecords
    let onSave: (DogRecords) -> Void
    @Environment(\.dismiss) private var dismiss

    static let maxPhotos = 4
    static let maxPDFBytes = 10 * 1024 * 1024

    @State private var items: [PhotosPickerItem] = []
    @State private var pickingPDF = false
    @State private var scanning = false
    @State private var draft: DogRecordDraft?
    @State private var keepVaccines: Set<Int> = []
    @State private var keepVisits: Set<Int> = []
    @State private var keepMeds: Set<Int> = []
    @State private var keepWeights: Set<Int> = []
    @State private var keepVet = true
    /// What was picked, kept so it can be saved to Documents
    @State private var pickedPages: [Data] = []
    @State private var pickedPDF: (data: Data, title: String)?
    @State private var keepDocument = true
    /// Why reading failed; the sheet then offers to save the document anyway
    @State private var failure: String?

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Import from your vet", theme: theme,
                    confirm: draft == nil ? nil : (label: "Save", enabled: selectedCount > 0 || keepVet, action: save), cancelDisabled: scanning) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let draft { review(draft, theme: theme) } else if let failure { failed(failure, theme: theme) } else { start(theme) }
                }
                .padding(16)
            }
        }
        .interactiveDismissDisabled(scanning)
        .onChange(of: items) { picked in
            guard !picked.isEmpty else { return }
            Task { @MainActor in await scanPhotos(picked) }
        }
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { @MainActor in await scanPDF(url) }
        }
    }

    // MARK: Step 1: pick

    private func start(_ theme: WidgetTheme) -> some View {
        let accent = context.accent
        return VStack(alignment: .leading, spacing: 16) {
            Text("🩺📄").font(.system(size: 44))
            Text("Snap your \(dogName.map { "\($0)'s" } ?? "dog's") vet paperwork").font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.label)
            Text("Vaccine certificates, visit summaries, invoices. We pull out vaccines and due dates, visits, medications, weight and your vet's details. You check everything before it's saved.")
                .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            if scanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the paperwork… (about 20 seconds)").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                }
                .padding(.vertical, 20)
            } else {
                PhotosPicker(selection: $items, maxSelectionCount: Self.maxPhotos, matching: .images) {
                    Label("Pick photos (up to \(Self.maxPhotos) pages)", systemImage: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
                Button { pickingPDF = true } label: {
                    Label("Choose a PDF the vet emailed", systemImage: "doc.richtext")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(context.accent, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                Text("Tip: in Mail, tap the PDF, then Share → Save to Files, and choose it here.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Text("The pages are read once to fill this in and aren't kept on our servers. What you save stays private to you.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Couldn't read it

    private func failed(_ message: String, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couldn't read it 🐾").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
            Text("\(message) You can still keep the paperwork with \(dogName ?? "your dog")'s records to look at anytime.")
                .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            Button { saveDocumentOnly() } label: {
                Label("Save it to \(dogName.map { "\($0)'s" } ?? "your dog's") documents", systemImage: "folder.badge.plus")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent))
            }
            .buttonStyle(.plain)
            Button { reset() } label: {
                Text("Try different pages").font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var hasPicked: Bool { !pickedPages.isEmpty || pickedPDF != nil }

    private func reset() {
        failure = nil; draft = nil; items = []; pickedPages = []; pickedPDF = nil
    }

    // MARK: Step 2: review

    @ViewBuilder
    private func review(_ draft: DogRecordDraft, theme: WidgetTheme) -> some View {
        if draft.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hmm, no records in there 🐾").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(theme.label)
                Text(draft.notes ?? "Try a clearer photo of the vaccine certificate or visit summary, or the PDF.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                Button("Try again") { reset() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                if hasPicked {
                    Button("Save it to \(dogName.map { "\($0)'s" } ?? "your dog's") documents anyway") { saveDocumentOnly() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                }
            }
        } else {
            if let pet = draft.petName, let dogName, !pet.isEmpty, pet.lowercased() != dogName.lowercased() {
                Label("These papers say \(pet), not \(dogName). Double-check before saving.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.warning)
            }
            Text("Uncheck anything that's wrong. Rows marked \"check this\" were hard to read.")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            if let notes = draft.notes, !notes.isEmpty {
                Text(notes).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).italic()
            }
            group("Vaccines", count: draft.vaccines.count, theme: theme) {
                ForEach(Array(draft.vaccines.enumerated()), id: \.offset) { i, v in
                    check($keepVaccines, i, title: v.name, detail: [v.givenOn.map { "Given \(DogDay.display($0, calendar: context.calendar) ?? $0)" },
                                                                    v.dueOn.map { "due \(DogDay.display($0, calendar: context.calendar) ?? $0)" }]
                        .compactMap { $0 }.joined(separator: " · "), unsure: v.unsure, theme: theme)
                }
            }
            group("Vet visits", count: draft.vetVisits.count, theme: theme) {
                ForEach(Array(draft.vetVisits.enumerated()), id: \.offset) { i, v in
                    check($keepVisits, i, title: v.reason ?? "Visit", detail: [v.date.flatMap { DogDay.display($0, calendar: context.calendar) }, v.clinic]
                        .compactMap { $0 }.joined(separator: " · "), unsure: v.unsure, theme: theme)
                }
            }
            group("Medications", count: draft.medications.count, theme: theme) {
                ForEach(Array(draft.medications.enumerated()), id: \.offset) { i, m in
                    check($keepMeds, i, title: [m.name, m.dose ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
                          detail: m.schedule ?? "", unsure: m.unsure, theme: theme)
                }
            }
            group("Weight", count: draft.weights.count, theme: theme) {
                ForEach(Array(draft.weights.enumerated()), id: \.offset) { i, w in
                    check($keepWeights, i, title: "\(w.lbs.formatted(.number.precision(.fractionLength(0...1)))) lb",
                          detail: w.date.flatMap { DogDay.display($0, calendar: context.calendar) } ?? "No date (skipped)", unsure: w.unsure, theme: theme)
                }
            }
            if let vet = draft.vet, !vet.isEmpty {
                Toggle(isOn: $keepVet) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vet: \(vet.clinic.isEmpty ? "details" : vet.clinic)").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text([vet.phone, vet.address].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Text("Fills in only what's blank.").font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
            }
            if hasPicked {
                Toggle(isOn: $keepDocument) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep the paperwork in Documents").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text("To look at or share anytime. It stays on this phone.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
            }
        }
    }

    private func group<C: View>(_ title: String, count: Int, theme: WidgetTheme, @ViewBuilder content: () -> C) -> some View {
        Group {
            if count > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetUI.header(title, theme: theme)
                    content()
                }
            }
        }
    }

    private func check(_ set: Binding<Set<Int>>, _ i: Int, title: String, detail: String, unsure: Bool, theme: WidgetTheme) -> some View {
        let on = set.wrappedValue.contains(i)
        return Button {
            if on { set.wrappedValue.remove(i) } else { set.wrappedValue.insert(i) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(on ? context.accent : theme.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel) }
                }
                Spacer()
                if unsure {
                    Text("check this").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.warning)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(theme.warning.opacity(0.15)))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        }
        .buttonStyle(.plain)
    }

    private var selectedCount: Int { keepVaccines.count + keepVisits.count + keepMeds.count + keepWeights.count + (hasPicked && keepDocument ? 1 : 0) }

    // MARK: Scanning

    private func scanPhotos(_ picked: [PhotosPickerItem]) async {
        scanning = true
        defer { scanning = false; items = [] }
        var pages: [Data] = []
        for item in picked.prefix(Self.maxPhotos) {
            if let data = try? await item.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data),
               let jpeg = EventImagePrep.jpeg(image) { pages.append(jpeg) }
        }
        guard !pages.isEmpty else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't read those photos", message: "Try picking them again."))
            return
        }
        pickedPages = pages; pickedPDF = nil
        await run { try await DogsClient(context: context).scanRecords(dogName: dogName, images: pages) }
    }

    private func scanPDF(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't open that PDF", message: "Try saving it to Files first."))
            return
        }
        guard data.count <= Self.maxPDFBytes else {
            context.host.presentAlert(WidgetAlert(title: "That PDF is too big", message: "Up to 10 MB. Try photos of the pages instead."))
            return
        }
        pickedPDF = (data, DogDocument.title(fromFileName: url.lastPathComponent)); pickedPages = []
        scanning = true
        defer { scanning = false }
        await run { try await DogsClient(context: context).scanRecords(dogName: dogName, pdf: data) }
    }

    private func run(_ scan: () async throws -> DogRecordDraft) async {
        do {
            let result = try await scan()
            keepVaccines = Set(result.vaccines.indices)
            keepVisits = Set(result.vetVisits.indices)
            keepMeds = Set(result.medications.indices)
            keepWeights = Set(result.weights.indices.filter { result.weights[$0].date != nil })
            keepVet = !(result.vet?.isEmpty ?? true)
            draft = result
            context.track("dog_records_scanned", ["rows": "\(result.vaccines.count + result.vetVisits.count + result.medications.count + result.weights.count)"])
        } catch {
            failure = DogErrors.message(error)
        }
    }

    // MARK: Step 3: save

    /// Writes what was picked to this phone; the clinic's name titles photos
    private func storedDocument(title: String?) -> DogDocument? {
        if let pickedPDF { return DogLocalPhotos.saveDocument(title: pickedPDF.title, pdf: pickedPDF.data) }
        let clean = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return DogLocalPhotos.saveDocument(title: clean.isEmpty ? DogDocument.defaultTitle : clean, pages: pickedPages)
    }

    private func saveDocumentOnly() {
        guard let doc = storedDocument(title: nil) else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't save it", message: "Try again in a moment."))
            return
        }
        var records = existing
        records.documents.append(doc)
        onSave(records)
        context.host.haptic(.success)
        context.track("dog_document_added", ["kind": doc.kind.rawValue, "from": "import"])
        dismiss()
    }

    private func save() {
        guard let draft else { return }
        var kept = draft
        kept.vaccines = draft.vaccines.enumerated().filter { keepVaccines.contains($0.offset) }.map(\.element)
        kept.vetVisits = draft.vetVisits.enumerated().filter { keepVisits.contains($0.offset) }.map(\.element)
        kept.medications = draft.medications.enumerated().filter { keepMeds.contains($0.offset) }.map(\.element)
        kept.weights = draft.weights.enumerated().filter { keepWeights.contains($0.offset) }.map(\.element)
        if !keepVet { kept.vet = nil }
        let result = DogRecordMerge.merge(kept, into: existing)
        var records = result.records
        if hasPicked && keepDocument, let doc = storedDocument(title: kept.vet?.clinic) { records.documents.append(doc) }
        onSave(records)
        context.host.haptic(.success)
        context.track("dog_records_imported", ["added": "\(result.added)", "skipped": "\(result.skipped)"])
        dismiss()
        if result.skipped > 0 {
            context.host.presentAlert(WidgetAlert(title: "Added \(result.added) record\(result.added == 1 ? "" : "s")",
                                                  message: "\(result.skipped) were already in \(dogName ?? "your dog")'s records, so we skipped them."))
        }
    }
}

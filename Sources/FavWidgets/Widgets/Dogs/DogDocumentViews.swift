import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FavWidgetsCore
#if canImport(PDFKit)
import PDFKit
#endif

enum DogDocumentLimits {
    static let maxPhotos = 4
    static let maxPDFBytes = 10 * 1024 * 1024
}

/// A dog's vet paperwork: the list (newest first), Add, and the viewer.
/// Shown at the top of the dog's page, and on its own from the document
/// button on each My Dogs row (Wes, 2026-10-23: "access the dog's documents
/// without even having to enter that dog's profile").
struct DogDocumentsPanel: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<DogsState>
    let dogId: String
    let dogName: String
    @State private var adding = false
    @State private var pickingPhotos = false
    @State private var pickingPDF = false
    @State private var items: [PhotosPickerItem] = []
    @State private var viewing: DogDocument?

    private var documents: [DogDocument] { state.model.records(for: dogId).documents }

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header("Documents", theme: theme)
                if !documents.isEmpty {
                    Button { adding = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(context.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a document")
                }
            }
            ForEach(documents.reversed()) { doc in
                Button { viewing = doc } label: { row(doc, theme: theme) }.buttonStyle(.plain)
            }
            if documents.isEmpty { addButton }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        .sheet(item: $viewing) { doc in
            DogDocumentViewer(context: context, document: doc, onRename: { title in
                update { docs in
                    if let i = docs.firstIndex(where: { $0.id == doc.id }) { docs[i].title = title }
                }
            }, onDelete: {
                update { $0.removeAll { $0.id == doc.id } }
                doc.files.forEach(DogLocalPhotos.delete)
            })
        }
        .confirmationDialog("Add a document", isPresented: $adding, titleVisibility: .visible) {
            Button("Photos of the pages") { pickingPhotos = true }
            Button("A PDF from Files") { pickingPDF = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vet invoices, visit summaries, vaccine certificates. Kept on this phone for \(dogName).")
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $items, maxSelectionCount: DogDocumentLimits.maxPhotos, matching: .images)
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            addPDF(url)
        }
        .onChange(of: items) { picked in
            guard !picked.isEmpty else { return }
            Task { @MainActor in await addPhotos(picked) }
        }
    }

    private var addButton: some View {
        Button { adding = true } label: {
            HStack(spacing: 12) {
                Text("🩺").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add vet paperwork").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("Invoices, visit summaries, vaccine certificates: snap the pages or pick the PDF. Daycare and boarders ask for these.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(.white)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent))
        }
        .buttonStyle(.plain)
    }

    private func row(_ doc: DogDocument, theme: WidgetTheme) -> some View {
        HStack(spacing: 12) {
            DogDocumentThumb(document: doc, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).lineLimit(2)
                Text(DogDocumentCopy.detail(doc, calendar: context.calendar)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
        }
        .contentShape(Rectangle())
    }

    private func addPhotos(_ picked: [PhotosPickerItem]) async {
        defer { items = [] }
        var pages: [Data] = []
        for item in picked {
            if let data = try? await item.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data),
               let jpeg = EventImagePrep.jpeg(image) { pages.append(jpeg) }
        }
        guard let doc = DogLocalPhotos.saveDocument(title: DogDocument.defaultTitle, pages: pages) else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't add those photos", message: "Try picking them again."))
            return
        }
        add(doc)
    }

    private func addPDF(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= DogDocumentLimits.maxPDFBytes,
              let doc = DogLocalPhotos.saveDocument(title: DogDocument.title(fromFileName: url.lastPathComponent), pdf: data) else {
            context.host.presentAlert(WidgetAlert(title: "Couldn't add that PDF", message: "Up to 10 MB. Try saving it to Files first."))
            return
        }
        add(doc)
    }

    private func add(_ doc: DogDocument) {
        update { $0.append(doc) }
        context.host.haptic(.success)
        context.track("dog_document_added", ["kind": doc.kind.rawValue])
    }

    private func update(_ change: @escaping (inout [DogDocument]) -> Void) {
        state.update { s in
            var r = s.records(for: dogId)
            change(&r.documents)
            s.records[dogId] = r
        }
    }
}

/// Just the documents, from the My Dogs row's document button.
struct DogDocumentsSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<DogsState>
    let dog: DogProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DogDocumentsPanel(context: context, state: state, dogId: dog.id, dogName: dog.name).padding(16)
            }
            .background(context.theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("\(dog.name)'s documents")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// A document's first page, small.
struct DogDocumentThumb: View {
    let document: DogDocument
    let theme: WidgetTheme
    @State private var image: PostcardPlatformImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.tertiaryBackground)
            if let image {
                Image(postcardImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: document.kind == .pdf ? "doc.richtext" : "doc.text.image").foregroundStyle(theme.secondaryLabel)
            }
        }
        .frame(width: 44, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: document.files.first) { image = DogDocumentPages.firstPage(document) }
    }
}

enum DogDocumentPages {
    /// The first page as an image: the first photo, or the PDF's first page
    static func firstPage(_ doc: DogDocument) -> PostcardPlatformImage? {
        guard let first = doc.files.first else { return nil }
        switch doc.kind {
        case .photos:
            return DogLocalPhotos.load(first).flatMap { PostcardPlatformImage(data: $0) }
        case .pdf:
            #if canImport(PDFKit)
            guard let url = DogLocalPhotos.url(first), let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 120, height: 160), for: .mediaBox)
            #else
            return nil
            #endif
        }
    }
}

/// Full view of a document: the pages (pinch to zoom on a PDF), with Share,
/// Rename and Delete.
struct DogDocumentViewer: View {
    let context: WidgetContext
    let document: DogDocument
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var title = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                pages
            }
            .widgetInlineNavigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        Button { newTitle = title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { confirming = true } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .onAppear { title = document.title }
        .confirmationDialog("Delete this document?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's only on this phone, so it can't be brought back.")
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                title = String(clean.prefix(80))
                onRename(title)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var pages: some View {
        switch document.kind {
        case .pdf:
            if let name = document.files.first, let url = DogLocalPhotos.url(name) {
                DogPDFView(url: url)
            } else {
                missing
            }
        case .photos:
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(document.files, id: \.self) { name in
                        if let image = DogLocalPhotos.load(name).flatMap({ PostcardPlatformImage(data: $0) }) {
                            Image(postcardImage: image).resizable().scaledToFit()
                        }
                    }
                }
            }
        }
    }

    private var missing: some View {
        Text("This document isn't on this phone.").foregroundStyle(.white.opacity(0.8))
    }

    private func share() {
        let items: [WidgetShareItem] = document.files.compactMap { name in
            switch document.kind {
            case .pdf: return DogLocalPhotos.url(name).map(WidgetShareItem.file)
            case .photos: return DogLocalPhotos.load(name).map(WidgetShareItem.imageJPEG)
            }
        }
        guard !items.isEmpty else { return }
        context.track("dog_document_shared", ["kind": document.kind.rawValue])
        context.host.share(items)
    }
}

#if canImport(PDFKit) && os(iOS)
/// PDFKit's viewer: scroll the pages, pinch to zoom.
struct DogPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .black
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#elseif canImport(PDFKit) && os(macOS)
struct DogPDFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
#endif

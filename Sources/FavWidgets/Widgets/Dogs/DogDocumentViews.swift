import SwiftUI
import FavWidgetsCore
#if canImport(PDFKit)
import PDFKit
#endif

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

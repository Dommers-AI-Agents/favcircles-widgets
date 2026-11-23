import SwiftUI
import PhotosUI
import FavWidgetsCore

/// "Scan a label" (Wes, 2026-11-23): snap prescription labels, AI reads them
/// into drafts, the person checks and edits each one in the normal editor,
/// confirms they checked, then adds. The warning stays on screen the whole
/// time; nothing is saved until "Add".
struct MedLabelScanSheet: View {
    let context: WidgetContext
    let existing: [Med]
    let onAdd: ([Med]) -> Void

    private enum Phase { case capture, reading, review(MedLabelReading) }

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .capture
    @State private var photos: [PostcardPlatformImage] = []
    @State private var cameraPhoto: PostcardPlatformImage?
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    /// Draft id → the medication as the person edited it
    @State private var edited: [String: Med] = [:]
    @State private var included: Set<String> = []
    @State private var editingDraft: MedLabelDraft?
    @State private var checked = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        WidgetSheet(title: "Scan a label", theme: theme, confirm: confirm) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    warning
                    switch phase {
                    case .capture: capture
                    case .reading: reading
                    case .review(let r): review(r)
                    }
                }
                .padding(16)
            }
        }
        .task {
            // Camera first; a cover presented on the sheet's very first frame can be dropped by UIKit
            #if os(iOS)
            if PostcardCameraPicker.isAvailable, photos.isEmpty {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !Task.isCancelled { showCamera = true }
            }
            #endif
        }
        #if os(iOS)
        .widgetCameraCover(isPresented: $showCamera) { PostcardCameraPicker(image: $cameraPhoto).ignoresSafeArea() }
        #endif
        .onChange(of: cameraPhoto) { photo in
            if let photo, photos.count < MedLabelScan.maxPhotos { photos.append(photo) }
            cameraPhoto = nil
        }
        .onChange(of: picked) { items in
            Task {
                for item in items where photos.count < MedLabelScan.maxPhotos {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data) {
                        photos.append(image)
                    }
                }
                picked = []
            }
        }
        .sheet(item: $editingDraft) { draft in
            MedEditSheet(context: context, med: edited[draft.id] ?? draft.med(), onSave: { med in
                edited[draft.id] = med
                if MedLabelScan.canAdd(med) { included.insert(draft.id) }
            }, onDelete: nil)
        }
    }

    // MARK: Warning (always shown)

    private var warning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(MedSafetyCopy.scanWarningTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.warning)
            Text(MedSafetyCopy.scanWarning).font(.system(size: 13)).foregroundStyle(theme.label)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.warning.opacity(0.12)))
    }

    // MARK: Capture

    private var capture: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photograph each prescription label or medicine box, flat and in good light. Up to \(MedLabelScan.maxPhotos) at once.")
                .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            #if os(iOS)
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.indices, id: \.self) { i in
                            Image(uiImage: photos[i]).resizable().scaledToFill().frame(width: 96, height: 128).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain).padding(4).accessibilityLabel("Remove photo")
                                }
                        }
                    }
                }
            }
            #endif
            if photos.count < MedLabelScan.maxPhotos {
                HStack(spacing: 10) {
                    #if os(iOS)
                    if PostcardCameraPicker.isAvailable {
                        Button { showCamera = true } label: { pill(photos.isEmpty ? "Take a photo" : "Another label", "camera.fill") }
                    }
                    #endif
                    PhotosPicker(selection: $picked, maxSelectionCount: MedLabelScan.maxPhotos - photos.count, matching: .images) {
                        pill("From photos", "photo.on.rectangle")
                    }
                }
                .buttonStyle(.plain)
            }
            if !photos.isEmpty {
                WidgetUI.primaryButton(photos.count == 1 ? "Read the label" : "Read \(photos.count) labels", color: context.accent) { read() }
            }
            Text(MedSafetyCopy.photoPrivacy).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private func pill(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(context.accent.opacity(0.12)))
    }

    private var reading: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Reading the label…").font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    // MARK: Review

    private func review(_ r: MedLabelReading) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if r.medications.isEmpty {
                Text(r.notes ?? "No medicine label found in those photos. Try again closer, flat and in good light, or add it by hand.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                WidgetUI.primaryButton("Try again", color: context.accent) { phase = .capture }
            } else {
                Text("Tap a medicine to check or change it. Ticked ones are added.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                ForEach(r.medications) { draft in row(draft) }
                if let notes = r.notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 13)).foregroundStyle(theme.warning)
                }
                if r.truncated {
                    Text("Some of the labels may not have been read. Scan fewer at once to be sure.")
                        .font(.system(size: 13)).foregroundStyle(theme.warning)
                }
                Toggle(isOn: $checked) {
                    Text(MedSafetyCopy.acknowledgement).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
                }
                .tint(context.accent)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
                Button("Scan different labels") { phase = .capture; checked = false }
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).buttonStyle(.plain)
            }
        }
    }

    private func row(_ draft: MedLabelDraft) -> some View {
        let med = edited[draft.id] ?? draft.med()
        let addable = MedLabelScan.canAdd(med)
        let on = included.contains(draft.id) && addable
        let duplicate = MedLabelScan.existing(draft, in: existing)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                guard addable else { editingDraft = draft; return }
                if on { included.remove(draft.id) } else { included.insert(draft.id) }
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24)).foregroundStyle(on ? context.accent : theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? "Don't add \(med.name)" : "Add \(med.name)")
            Button { editingDraft = draft } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                    Text(med.times.isEmpty ? "No reminder time yet · tap to set one" : MedSchedule.summary(med, calendar: context.calendar))
                        .font(.system(size: 13)).foregroundStyle(med.times.isEmpty ? theme.warning : theme.secondaryLabel)
                    if let directions = draft.directions {
                        Text("Label: “\(directions)”").font(.system(size: 12)).italic().foregroundStyle(theme.secondaryLabel)
                    }
                    if edited[draft.id] == nil, let why = draft.why {
                        Text(why).font(.system(size: 12)).foregroundStyle(draft.unsure ? theme.warning : theme.secondaryLabel)
                    }
                    if draft.unsure {
                        Label("Hard to read: check this one carefully", systemImage: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.warning)
                    }
                    if duplicate != nil {
                        Label("Already in your list. Adding it again doubles its reminders.", systemImage: "square.on.square")
                            .font(.system(size: 12)).foregroundStyle(theme.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel).padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    // MARK: Actions

    private var chosen: [Med] {
        guard case .review(let r) = phase else { return [] }
        return r.medications.filter { included.contains($0.id) }.map { edited[$0.id] ?? $0.med() }.filter(MedLabelScan.canAdd)
    }

    private var confirm: (label: String, enabled: Bool, action: () -> Void)? {
        guard case .review(let r) = phase, !r.medications.isEmpty else { return nil }
        let count = chosen.count
        return (count > 1 ? "Add \(count)" : "Add", checked && count > 0, add)
    }

    private func read() {
        let images = photos.compactMap(Self.upload)
        guard !images.isEmpty else { return }
        phase = .reading
        context.track("med_label_scan", ["photos": "\(images.count)"])
        Task { @MainActor in
            do {
                let response: MedLabelReading.Response = try await context.api(.post, "widgets/meds/scan", body: ["images": images])
                let r = response.reading
                edited = [:]; checked = false
                included = Set(r.medications.filter { $0.includedByDefault && MedLabelScan.existing($0, in: existing) == nil }.map(\.id))
                phase = .review(r)
            } catch {
                phase = .capture
                context.host.presentAlert(WidgetAlert(title: "Couldn't read the label", message: (error as NSError).localizedDescription))
            }
        }
    }

    private func add() {
        let meds = chosen
        guard checked, !meds.isEmpty else { return }
        onAdd(meds)
        context.host.haptic(.success)
        context.track("med_label_added", ["count": "\(meds.count)"])
        dismiss()
    }

    /// JPEG at the server's reading size, base64.
    private static func upload(_ image: PostcardPlatformImage) -> String? {
        #if os(iOS)
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, CGFloat(MedLabelScan.uploadLongEdge) / max(longest, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)?.base64EncodedString()
        #else
        return nil
        #endif
    }
}

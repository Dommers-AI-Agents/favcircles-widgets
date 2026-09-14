import SwiftUI
import PhotosUI
import FavWidgetsCore

/// The compose flow: photo → template → caption → message → recipient →
/// send, with the sent history underneath. The photo is memory-only; the
/// rest of the draft is mirrored into `PostcardSettings.draft` through the
/// controller's debounced `update` so a half-written card survives.
struct PostcardFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<PostcardSettings>
    @ObservedObject var currentMonth: WidgetStateController<PostcardMonth>
    @ObservedObject var previousMonth: WidgetStateController<PostcardMonth>

    // Compose state (photo never leaves memory).
    @State private var photo: PostcardPlatformImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var templateId = PostcardTemplate.classic.rawValue
    @State private var placeName = ""
    @State private var placeRef: WidgetPlaceRef?
    @State private var message = ""
    @State private var recipient: WidgetContact?
    @State private var showRecipientPicker = false
    @State private var draftId = UUID()
    @State private var hasSeeded = false

    // Send state.
    @State private var isSending = false
    @State private var sentRecord: PostcardRecord?

    // History.
    @State private var extraMonths: [MonthKey] = []
    @State private var selectedRecord: PostcardRecord?

    var body: some View {
        let theme = context.theme
        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WidgetSyncBadge(state: settings.syncState, theme: theme)
                    if let sentRecord {
                        sentPanel(sentRecord, theme: theme)
                    } else {
                        photoSection(theme)
                        templateSection(theme)
                        captionSection(theme)
                        messageSection(theme)
                        recipientSection(theme)
                        sendSection(theme)
                    }
                    historySection(theme)
                    Color.clear.frame(height: 24)
                }
                .padding(16)
            }
            .disabled(isSending)
            if isSending {
                sendingOverlay(theme)
            }
        }
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task { await seed() }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .onChange(of: templateId) { id in
            guard hasSeeded else { return }
            settings.update { $0.lastTemplateId = id }
            persistDraft()
        }
        .onChange(of: message) { text in
            if text.count > PostcardCopy.messageLimit {
                message = String(text.prefix(PostcardCopy.messageLimit))
                return
            }
            persistDraft()
        }
        .onChange(of: placeName) { _ in persistDraft() }
        .onChange(of: recipient) { _ in persistDraft() }
        .sheet(isPresented: $showRecipientPicker) {
            PostcardRecipientPicker(context: context, selectedId: recipient?.id) { contact in
                recipient = contact
                context.host.haptic(.selection)
            }
        }
        .widgetCameraCover(isPresented: $showCamera) {
            #if os(iOS)
            PostcardCameraPicker(image: $photo).ignoresSafeArea()
            #else
            EmptyView()
            #endif
        }
        .sheet(item: $selectedRecord) { record in
            PostcardRecordDetail(context: context, record: record)
        }
    }

    // MARK: - Derived

    private var caption: String { PostcardCopy.caption(placeName: placeName) }
    private var canSend: Bool { photo != nil && recipient != nil && !isSending }

    /// The place stamped on the draft and the record: the known place with
    /// the (possibly edited) name, or a custom-id ref for a typed-in name.
    private var placeForRecord: WidgetPlaceRef? {
        let name = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let placeRef, !PostcardCopy.isCustom(placeRef) {
            return WidgetPlaceRef(id: placeRef.id, name: name, city: placeRef.city, isGlobal: placeRef.isGlobal)
        }
        return WidgetPlaceRef(id: PostcardCopy.customPlaceId, name: name, city: nil, isGlobal: false)
    }

    /// Only real FavCircles places cross the host boundary.
    private var placeForHost: WidgetPlaceRef? {
        guard let place = placeForRecord, !PostcardCopy.isCustom(place) else { return nil }
        return place
    }

    // MARK: - Sections

    private func photoSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Photo", theme: theme)
            preview
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    secondaryLabel(photo == nil ? "Choose photo" : "Change photo", symbol: "photo.on.rectangle", theme: theme)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                if PostcardCameraPicker.isAvailable {
                    Button { showCamera = true } label: {
                        secondaryLabel("Take photo", symbol: "camera", theme: theme)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            PostcardCanvasView(image: photo, templateId: templateId, caption: caption,
                               size: CGSize(width: proxy.size.width, height: proxy.size.width / PostcardTemplate.aspectRatio),
                               accent: context.accent)
        }
        .aspectRatio(PostcardTemplate.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    private func templateSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Template", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PostcardTemplate.allCases) { template in
                        let selected = template.rawValue == templateId
                        Button {
                            templateId = template.rawValue
                            context.host.haptic(.selection)
                        } label: {
                            VStack(spacing: 6) {
                                PostcardCanvasView(image: photo, templateId: template.rawValue, caption: caption,
                                                   size: CGSize(width: 132, height: 88), accent: context.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(selected ? context.accent : theme.separator, lineWidth: selected ? 3 : 1)
                                    )
                                Text(template.name)
                                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? context.accent : theme.secondaryLabel)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(template.name) template")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func captionSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Caption on the card", theme: theme)
            HStack(spacing: 8) {
                Text("Greetings from")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.secondaryLabel)
                TextField("Where are you?", text: $placeName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.label)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            if let placeRef, !PostcardCopy.isCustom(placeRef) {
                Label(placeRef.city.map { "\(placeRef.name), \($0)" } ?? placeRef.name, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    private func messageSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header("Message", theme: theme)
                Text("\(message.count)/\(PostcardCopy.messageLimit)")
                    .font(.system(size: 12))
                    .foregroundStyle(message.count >= PostcardCopy.messageLimit ? theme.warning : theme.secondaryLabel)
            }
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("Wish you were here…")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.secondaryLabel.opacity(0.6))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
                TextEditor(text: $message)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.label)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private func recipientSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("To", theme: theme)
            Button { showRecipientPicker = true } label: {
                HStack(spacing: 12) {
                    if let recipient {
                        PostcardContactRow(contact: recipient, theme: theme, accent: context.accent)
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(context.accent)
                        Text("Choose a connection")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.label)
                        Spacer()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func sendSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.primaryButton("Send postcard", color: context.accent) {
                Task { await send() }
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
            if photo == nil || recipient == nil {
                Text(photo == nil ? "Add a photo to send." : "Choose who to send it to, or share it by text or email.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
            // Anyone, not just FavCircles users: the rendered postcard goes
            // out through the system share sheet (Messages, Mail, …).
            Button { share() } label: {
                Label("Share by text or email", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(photo == nil || isSending)
            .opacity(photo == nil ? 0.5 : 1)
        }
    }

    /// Renders the postcard and hands it (plus the note) to the share sheet.
    private func share() {
        guard let photo else { return }
        do {
            let jpeg = try PostcardRendering.jpeg(image: photo, templateId: templateId, caption: caption, accent: context.accent)
            var lines: [String] = []
            let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { lines.append(note) }
            lines.append(caption.isEmpty ? "📮 A postcard for you" : "📮 \(caption)")
            lines.append("Sent with FavCircles — https://favcircles.com/")
            context.track("postcard_shared", ["template_id": templateId])
            context.host.haptic(.light)
            context.host.share([.imageJPEG(jpeg), .text(lines.joined(separator: "\n"))])
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't share", message: error.localizedDescription))
        }
    }

    private func sentPanel(_ record: PostcardRecord, theme: WidgetTheme) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.success)
            Text("Sent!")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.label)
            Text("Your postcard is on its way to \(record.recipientName).")
                .font(.system(size: 15))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
            WidgetUI.primaryButton("Send another", color: context.accent) {
                sentRecord = nil
            }
            Button("Done") { context.closeFullView() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(context.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
    }

    private func historySection(_ theme: WidgetTheme) -> some View {
        let months = [context.currentMonth, context.currentMonth.previous] + extraMonths
        let preloadedEmpty = currentMonth.model.sent.isEmpty && previousMonth.model.sent.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Sent", theme: theme)
            if preloadedEmpty && extraMonths.isEmpty && currentMonth.hasLoaded && previousMonth.hasLoaded {
                Text("Postcards you send show up here.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryLabel)
            }
            ForEach(months, id: \.rawValue) { month in
                PostcardMonthRows(context: context, month: month,
                                  controller: context.month(PostcardMonth.self, month)) { record in
                    selectedRecord = record
                }
            }
            Button {
                extraMonths.append((extraMonths.last ?? context.currentMonth.previous).previous)
                context.track("postcard_history_earlier", ["months": "\(extraMonths.count)"])
            } label: {
                Label("Earlier", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(context.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func sendingOverlay(_ theme: WidgetTheme) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(theme.primary)
                Text("Sending…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.label)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.background))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
    }

    private func secondaryLabel(_ title: String, symbol: String, theme: WidgetTheme) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(context.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(context.accent.opacity(0.12)))
    }

    // MARK: - Seeding & draft

    private func seed() async {
        await settings.loadIfNeeded()
        guard !hasSeeded else { return }
        let model = settings.model
        if let draft = model.draft {
            draftId = draft.id
            templateId = draft.templateId
            message = String(draft.message.prefix(PostcardCopy.messageLimit))
            placeRef = draft.place
            placeName = draft.place?.name ?? ""
            if let id = draft.recipientId {
                recipient = WidgetContact(id: id, displayName: draft.recipientName ?? "Connection")
            }
        } else {
            templateId = model.lastTemplateId
        }
        hasSeeded = true
        if placeRef == nil, let nearby = await context.host.nearbyOrCurrentPlace() {
            placeRef = nearby
            if placeName.isEmpty { placeName = nearby.name }
        }
    }

    private func persistDraft() {
        guard hasSeeded else { return }
        let hasContent = !message.isEmpty || recipient != nil || PostcardCopy.isCustom(placeForRecord)
            || (placeRef != nil && placeForRecord?.name != placeRef?.name)
        let draft: PostcardDraft? = hasContent
            ? PostcardDraft(id: draftId, templateId: templateId, message: message,
                            recipientId: recipient?.id, recipientName: recipient?.displayName,
                            place: placeForRecord, updatedAt: Date())
            : nil
        settings.update { current in
            if let draft {
                // Keep the stored timestamp unless something actually changed.
                if var existing = current.draft, existing.id == draft.id {
                    existing.updatedAt = draft.updatedAt
                    if existing == draft { return }
                }
                current.draft = draft
            } else {
                current.draft = nil
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = PostcardPlatformImage(data: data) else {
                context.host.presentAlert(WidgetAlert(title: "Couldn't load photo", message: "That photo couldn't be read. Try another one."))
                return
            }
            photo = image
            context.host.haptic(.light)
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't load photo", message: error.localizedDescription))
        }
    }

    // MARK: - Send

    private func send() async {
        guard let photo, let recipient, !isSending else { return }
        isSending = true
        defer { isSending = false }
        let templateId = templateId
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordPlace = placeForRecord
        do {
            let jpeg = try PostcardRendering.jpeg(image: photo, templateId: templateId, caption: caption, accent: context.accent)
            let receipt = try await context.host.sendPostcard(WidgetPostcardSend(
                recipientId: recipient.id, imageJPEG: jpeg, message: message, templateId: templateId, place: placeForHost
            ))
            let record = PostcardRecord(
                messageId: receipt.messageId, conversationId: receipt.conversationId,
                recipientId: recipient.id, recipientName: recipient.displayName,
                templateId: templateId, message: message, imageURL: receipt.imageURL,
                place: recordPlace, sentAt: Date()
            )
            context.month(PostcardMonth.self, context.currentMonth).update { $0.sent.append(record) }
            settings.update {
                $0.draft = nil
                $0.lastTemplateId = templateId
            }
            context.host.haptic(.success)
            context.track("postcard_sent", ["template_id": templateId, "has_place": placeForHost == nil ? "false" : "true"])
            sentRecord = record
            resetCompose()
        } catch {
            context.host.haptic(.warning)
            context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: error.localizedDescription))
        }
    }

    /// Clears everything except the place (the user is still on the same
    /// trip) and the template.
    private func resetCompose() {
        photo = nil
        photoItem = nil
        self.message = ""
        recipient = nil
        draftId = UUID()
    }
}

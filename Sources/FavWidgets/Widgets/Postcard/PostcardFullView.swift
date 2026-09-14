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
    @State private var emailText = ""
    @State private var alsoShare = false

    // Mail a printed card. The config arrives from the server so the price
    // and the cancel window are never hardcoded here, and the whole option
    // stays hidden until the vendor accounts are live.
    @State private var mailConfig: PostcardMail.Config?
    @State private var mailOn = false
    @State private var mailAddress = PostcardMailAddress()
    @State private var mailQuote: PostcardMail.Quote?
    @State private var mailQuoteError: String?
    @State private var isQuoting = false
    @State private var quoteTask: Task<Void, Never>?
    /// Uploaded while the person fills in the address, so the Send tap can
    /// open Apple Pay with no network call in front of it.
    @State private var printImageURL: URL?
    @State private var printUploadTask: Task<Void, Never>?
    @State private var draftId = UUID()
    @State private var hasSeeded = false

    // Send state.
    @State private var isSending = false
    @State private var isSharing = false
    @State private var isCancelingMail = false
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
        .task { await loadMailConfig() }
        .onChange(of: mailOn) { on in
            // Start the print upload as soon as they opt in: it has to be
            // finished before the Send tap, because Apple Pay can't be
            // presented after an await.
            if on { schedulePrintUpload() }
        }
        .onChange(of: photo) { _ in
            printImageURL = nil
            if mailOn { schedulePrintUpload() }
        }
        .onChange(of: templateId) { _ in
            printImageURL = nil
            if mailOn { schedulePrintUpload() }
        }
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
    private var emailAddresses: (valid: [String], invalid: [String]) { PostcardEmail.parse(emailText) }
    private var canSend: Bool {
        photo != nil && !isSending && emailAddresses.invalid.isEmpty
            && (recipient != nil || !emailAddresses.valid.isEmpty || canMail)
            && emailAddresses.valid.count <= PostcardEmail.maxAddresses
    }

    /// The paid option is offered only when the server has it switched on
    /// and this device can actually pay. A dead button is worse than no
    /// button.
    private var mailAvailable: Bool {
        (mailConfig?.isUsable ?? false) && context.host.supportsPayment
    }

    private var canMail: Bool {
        mailOn && mailAvailable && mailAddress.isComplete
    }

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
            WidgetUI.header("Deliver to", theme: theme)
            Text("Pick any or all — one Send does them together.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
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
            if recipient != nil {
                Button("Remove connection") { recipient = nil }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryLabel)
            }

            // Email: anyone, FavCircles user or not. The app sends the mail.
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(context.accent)
                TextField("Email addresses, comma separated", text: $emailText)
                    .font(.system(size: 16))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            if !emailAddresses.invalid.isEmpty {
                Text("Check: \(emailAddresses.invalid.joined(separator: ", "))")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
            } else if emailAddresses.valid.count > PostcardEmail.maxAddresses {
                Text("Up to \(PostcardEmail.maxAddresses) addresses per postcard.")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
            } else if !emailAddresses.valid.isEmpty {
                Text("Will email \(emailAddresses.valid.count == 1 ? emailAddresses.valid[0] : "\(emailAddresses.valid.count) people") with a link to view it online.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }

            if mailAvailable, let mailConfig {
                PostcardMailForm(
                    theme: theme,
                    accent: context.accent,
                    config: mailConfig,
                    isOn: $mailOn,
                    address: $mailAddress,
                    quote: mailQuote,
                    quoteError: mailQuoteError,
                    isQuoting: isQuoting,
                    onAddressSettled: scheduleQuote
                )
            }

            Toggle(isOn: $alsoShare) {
                Text("Also share by text or other apps after sending")
                    .font(.system(size: 14)).foregroundStyle(theme.label)
            }
            .tint(context.accent)
        }
    }

    private func sendSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.primaryButton("Send postcard", color: context.accent) {
                Task { await send() }
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
            if photo == nil || (recipient == nil && emailAddresses.valid.isEmpty) {
                Text(photo == nil ? "Add a photo to send." : "Choose a connection and/or enter an email, or just share the card.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
            // Share only: the rendered card plus a link, through the system
            // share sheet (Messages, WhatsApp, Mail, …).
            Button { share() } label: {
                Label("Share the card", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(photo == nil || isSending || isSharing)
            .opacity(photo == nil ? 0.5 : 1)
            if isSharing {
                HStack(spacing: 8) { ProgressView(); Text("Preparing your postcard…") }
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    /// Renders the postcard, publishes a public page for it, and hands the
    /// image plus a link to the share sheet. Non-users open the link in a
    /// browser and see the card with the FavCircles pitch underneath. If
    /// the page can't be made, the image still goes out.
    private func share() {
        guard let photo, !isSharing else { return }
        isSharing = true
        Task {
            defer { isSharing = false }
            do {
                let jpeg = try PostcardRendering.jpeg(image: photo, templateId: templateId, caption: caption, accent: context.accent)
                let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
                let link = await PostcardShareLink.create(context: context, jpeg: jpeg, message: note, templateId: templateId, place: placeForHost)
                shareCard(jpeg: jpeg, note: note, link: link)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't share", message: error.localizedDescription))
            }
        }
    }

    private func shareCard(jpeg: Data, note: String, link: URL?) {
        var lines: [String] = []
        if !note.isEmpty { lines.append(note) }
        lines.append(caption.isEmpty ? "📮 A postcard for you" : "📮 \(caption)")
        if let link {
            lines.append("See it here: \(link.absoluteString)")
        } else {
            lines.append("Sent with FavCircles — https://favcircles.com/")
        }
        context.track("postcard_shared", ["template_id": templateId, "has_link": link == nil ? "false" : "true"])
        context.host.haptic(.light)
        context.host.share([.imageJPEG(jpeg), .text(lines.joined(separator: "\n"))])
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

            if let order = record.mailOrder {
                VStack(spacing: 8) {
                    Label(order.displayStatus, systemImage: "envelope.badge.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.label)
                        .multilineTextAlignment(.center)
                    if order.status.isCancelable {
                        Button {
                            Task { await cancelMail(order) }
                        } label: {
                            Text(isCancelingMail ? "Canceling…" : "Cancel the printed card")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.danger)
                        }
                        .disabled(isCancelingMail)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.background))
            }

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

    /// One Send, every selected route: in-app to a connection, email to
    /// typed addresses, then optionally the share sheet. Each route records
    /// its own history entry; a failure in one doesn't undo the others.
    private func send() async {
        guard let photo, canSend else { return }
        isSending = true
        defer { isSending = false }
        let templateId = templateId
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordPlace = placeForRecord
        let emails = emailAddresses.valid
        let jpeg: Data
        do {
            jpeg = try PostcardRendering.jpeg(image: photo, templateId: templateId, caption: caption, accent: context.accent)
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: error.localizedDescription))
            return
        }

        var records: [PostcardRecord] = []
        var failures: [String] = []
        var pageLink: URL?
        var mailOrder: PostcardMailOrder?

        // Paid first, and everything else only after it succeeds. The free
        // routes go out an hour before anything is printed, so letting them
        // run after a dismissed wallet would tell the recipient a card is in
        // the mail when none is.
        if canMail {
            switch await mailPrintedCard(message: message, place: placeForHost) {
            case .success(let order):
                guard let order else {
                    // Wallet dismissed. Their choice, nothing held, nothing
                    // sent; leave the draft exactly as it was.
                    context.host.haptic(.warning)
                    return
                }
                mailOrder = order
                records.append(PostcardRecord(
                    messageId: "mail:\(order.orderId)", conversationId: "",
                    recipientId: "mail", recipientName: order.recipientName,
                    templateId: templateId, message: message, imageURL: nil,
                    place: recordPlace, sentAt: Date(), mailOrder: order
                ))
            case .failure(let error):
                context.host.haptic(.warning)
                context.host.presentAlert(WidgetAlert(
                    title: "Couldn't mail that card",
                    message: "\(error.localizedDescription)\n\nYou haven't been charged. Nothing else was sent either — try again when you're ready."
                ))
                return
            }
        }

        if let recipient {
            do {
                let receipt = try await context.host.sendPostcard(WidgetPostcardSend(
                    recipientId: recipient.id, imageJPEG: jpeg, message: message, templateId: templateId, place: placeForHost
                ))
                records.append(PostcardRecord(
                    messageId: receipt.messageId, conversationId: receipt.conversationId,
                    recipientId: recipient.id, recipientName: recipient.displayName,
                    templateId: templateId, message: message, imageURL: receipt.imageURL,
                    place: recordPlace, sentAt: Date()
                ))
            } catch {
                failures.append("to \(recipient.displayName): \(error.localizedDescription)")
            }
        }

        if !emails.isEmpty {
            do {
                let result = try await PostcardEmail.send(context: context, jpeg: jpeg, emails: emails, message: message, templateId: templateId, place: placeForHost)
                pageLink = result.url.flatMap(URL.init(string:))
                if !result.sent.isEmpty {
                    records.append(PostcardRecord(
                        messageId: "email:\(UUID().uuidString)", conversationId: "",
                        recipientId: "email", recipientName: result.sent.joined(separator: ", "),
                        templateId: templateId, message: message, imageURL: pageLink,
                        place: recordPlace, sentAt: Date()
                    ))
                }
                if let failed = result.failed, !failed.isEmpty {
                    failures.append("email to \(failed.joined(separator: ", ")) didn't go through")
                }
            } catch {
                failures.append("email: \(error.localizedDescription)")
            }
        }

        guard !records.isEmpty else {
            context.host.haptic(.warning)
            context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: failures.joined(separator: "\n")))
            return
        }

        context.month(PostcardMonth.self, context.currentMonth).update { $0.sent.append(contentsOf: records) }
        settings.update {
            $0.draft = nil
            $0.lastTemplateId = templateId
        }
        context.host.haptic(.success)
        context.track("postcard_sent", ["template_id": templateId, "has_place": placeForHost == nil ? "false" : "true",
                                        "in_app": recipient == nil ? "0" : "1", "emails": "\(emails.count)",
                                        "mailed": mailOrder == nil ? "0" : "1"])
        if !failures.isEmpty {
            context.host.presentAlert(WidgetAlert(title: "Sent, with one problem", message: failures.joined(separator: "\n")))
        }

        // Summary line for the sent panel: "Ana and 2 email addresses".
        var parts: [String] = []
        if let recipient, records.contains(where: { $0.recipientId == recipient.id }) { parts.append(recipient.displayName) }
        if let mailed = records.first(where: { $0.recipientId == "email" }) {
            let count = mailed.recipientName.split(separator: ",").count
            parts.append(count == 1 ? mailed.recipientName : "\(count) email addresses")
        }
        if let mailOrder { parts.append("\(mailOrder.recipientName) by mail") }
        var summary = records[0]
        summary.recipientName = parts.joined(separator: " and ")
        summary.mailOrder = mailOrder
        sentRecord = summary

        if alsoShare {
            shareCard(jpeg: jpeg, note: message, link: pageLink)
        }
        resetCompose()
    }

    // MARK: - Mail a printed card

    private func loadMailConfig() async {
        guard mailConfig == nil else { return }
        // A failure here just means no paid option this session. It is never
        // worth an alert: every free route still works.
        mailConfig = try? await PostcardMail.config(context: context)
    }

    /// Re-checks the address a beat after typing stops. The check is metered
    /// on the vendor's side, so it runs once per settled address rather than
    /// once per keystroke.
    private func scheduleQuote() {
        quoteTask?.cancel()
        mailQuote = nil
        mailQuoteError = nil
        guard mailOn, mailAddress.isComplete else { return }
        let address = mailAddress
        quoteTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            isQuoting = true
            defer { isQuoting = false }
            do {
                let quote = try await PostcardMail.quote(context: context, address: address)
                guard !Task.isCancelled else { return }
                mailQuote = quote
            } catch {
                guard !Task.isCancelled else { return }
                mailQuoteError = error.localizedDescription
            }
        }
    }

    /// Renders and uploads the 300 DPI card. Deliberately eager and
    /// discardable — it costs one upload and buys a Send tap that opens the
    /// wallet instantly.
    private func schedulePrintUpload() {
        printUploadTask?.cancel()
        guard let photo, printImageURL == nil else { return }
        let templateId = templateId
        let caption = caption
        printUploadTask = Task {
            guard let jpeg = try? PostcardRendering.printJPEG(
                image: photo, templateId: templateId, caption: caption, accent: context.accent) else { return }
            guard !Task.isCancelled else { return }
            printImageURL = try? await PostcardMail.prepareArtwork(context: context, jpeg: jpeg)
        }
    }

    /// Runs the paid leg. Returns the order, or nil when the person dismissed
    /// the wallet or something went wrong — the caller treats nil as "don't
    /// send the free routes either", because a card that says it's in the
    /// mail must not go out before the mail is paid for.
    private func mailPrintedCard(message: String, place: WidgetPlaceRef?) async -> Result<PostcardMailOrder?, Error> {
        guard let mailConfig else { return .success(nil) }
        // The upload usually finished while they typed the address; wait for
        // it only if it didn't.
        if printImageURL == nil {
            await printUploadTask?.value
        }
        guard let printImageURL else {
            return .failure(WidgetAPIError(status: 500, message: "The printed card couldn't be prepared."))
        }
        let prepared = PostcardMail.Prepared(
            printImageURL: printImageURL,
            address: mailQuote?.deliverable == true ? applyingName(mailQuote!.address) : mailAddress,
            config: mailConfig
        )
        do {
            return .success(try await PostcardMail.purchase(
                context: context, prepared: prepared, message: message, templateId: templateId, place: place))
        } catch {
            return .failure(error)
        }
    }

    /// Pulls a printed card back before it goes to the printer. The server
    /// decides whether that's still allowed — it checks the order's status,
    /// not the clock, so a card already claimed for printing can't be voided
    /// out from under itself.
    private func cancelMail(_ order: PostcardMailOrder) async {
        guard !isCancelingMail else { return }
        isCancelingMail = true
        defer { isCancelingMail = false }
        do {
            let updated = try await PostcardMail.cancel(context: context, orderId: order.orderId).asRecordOrder
            sentRecord?.mailOrder = updated
            updateStoredMailOrder(updated)
            context.host.haptic(.success)
        } catch {
            context.host.presentAlert(WidgetAlert(
                title: "Couldn't cancel",
                message: error.localizedDescription))
        }
    }

    /// Keeps the history row in step with the live order.
    private func updateStoredMailOrder(_ order: PostcardMailOrder) {
        context.month(PostcardMonth.self, context.currentMonth).update { month in
            for index in month.sent.indices where month.sent[index].mailOrder?.orderId == order.orderId {
                month.sent[index].mailOrder = order
            }
        }
    }

    /// The postal service standardizes the street but doesn't know the
    /// person's name, so keep the typed one.
    private func applyingName(_ standardized: PostcardMailAddress) -> PostcardMailAddress {
        var address = standardized
        address.name = mailAddress.normalized.name
        return address
    }

    /// Clears everything except the place (the user is still on the same
    /// trip) and the template.
    private func resetCompose() {
        photo = nil
        photoItem = nil
        self.message = ""
        recipient = nil
        emailText = ""
        alsoShare = false
        mailOn = false
        mailAddress = PostcardMailAddress()
        mailQuote = nil
        mailQuoteError = nil
        printImageURL = nil
        draftId = UUID()
    }
}

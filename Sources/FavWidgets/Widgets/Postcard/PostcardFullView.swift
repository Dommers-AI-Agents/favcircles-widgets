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
    @State var photo: PostcardPlatformImage?
    @State var photoItem: PhotosPickerItem?
    @State var showCamera = false
    @State var templateId = PostcardTemplate.classic.rawValue
    @State var placeName = ""
    @State var placeRef: WidgetPlaceRef?
    @State var message = ""
    @State var recipient: WidgetContact?
    @State var showRecipientPicker = false
    @State var emailText = ""
    @State var alsoShare = false

    // Mail a printed card. The config arrives from the server so the price
    // and the cancel window are never hardcoded here, and the whole option
    // stays hidden until the vendor accounts are live.
    @State var mailConfig: PostcardMail.Config?
    @State var mailOn = false
    @State var mailAddress = PostcardMailAddress()
    @State var mailQuote: PostcardMail.Quote?
    @State var mailQuoteError: String?
    @State var isQuoting = false
    @State var quoteTask: Task<Void, Never>?
    /// Uploaded while the person fills in the address, so the Send tap can
    /// open Apple Pay with no network call in front of it.
    @State var printImageURL: URL?
    @State var printUploadTask: Task<Void, Never>?
    @State var draftId = UUID()
    @State var hasSeeded = false

    // Send state.
    @State var isSending = false
    @State var isSharing = false
    @State var isCancelingMail = false
    @State var sentRecord: PostcardRecord?

    // History.
    @State var extraMonths: [MonthKey] = []
    @State var selectedRecord: PostcardRecord?

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

    var caption: String { PostcardCopy.caption(placeName: placeName) }
    var emailAddresses: (valid: [String], invalid: [String]) { PostcardEmail.parse(emailText) }
    /// The rule itself lives in FavWidgetsCore, under test — it has been wrong
    /// twice, once refusing with a reason that contradicted the screen and once
    /// allowing a send that quietly dropped the printed card.
    var canSend: Bool {
        PostcardSendGate.canSend(.init(
            hasPhoto: photo != nil,
            isSending: isSending,
            hasInvalidEmail: !emailAddresses.invalid.isEmpty,
            tooManyEmails: emailAddresses.valid.count > PostcardEmail.maxAddresses,
            hasDigitalRecipient: recipient != nil || !emailAddresses.valid.isEmpty,
            mailRequested: mailOn && mailAvailable,
            mailReady: canMail
        ))
    }

    /// They asked for a printed card and it isn't mailable yet — used by the
    /// hint so it explains the wait rather than leaving a dead button.
    var mailRequestedButNotReady: Bool {
        mailOn && mailAvailable && !canMail
    }

    /// The paid option is offered only when the server has it switched on
    /// and this device can actually pay. A dead button is worse than no
    /// button.
    var mailAvailable: Bool {
        (mailConfig?.isUsable ?? false) && context.host.supportsPayment
    }

    /// Everything the server will insist on, checked here first.
    ///
    /// The order is created *inside* the Apple Pay sheet, so anything this
    /// misses surfaces after the person has already authorized with Face ID.
    /// Letting them pay for a card we already know is undeliverable, or for a
    /// message we already know is too long, is the worst version of this
    /// feature.
    var canMail: Bool {
        mailOn && mailAvailable && mailAddress.isComplete
            && mailQuote?.deliverable == true
            && !mailCorrectionPending
            && !mailMessageTooLong
    }

    /// The postal service found a different place from the one typed — a
    /// different ZIP, city, state or house number — and the person hasn't
    /// accepted it yet. A Charlotte ZIP under a New Jersey street used to sail
    /// through here: verification "fixed" it, the card was sendable, and it
    /// would have gone to an address the person never saw.
    var mailCorrectionPending: Bool {
        guard let quote = mailQuote, quote.deliverable else { return false }
        return quote.address.differsMaterially(from: mailAddress)
    }

    /// The printed back holds less than the digital card's 500 characters.
    var mailMessageTooLong: Bool {
        guard let limit = mailConfig?.messageMaxChars else { return false }
        return message.trimmingCharacters(in: .whitespacesAndNewlines).count > limit
    }

    /// The place stamped on the draft and the record: the known place with
    /// the (possibly edited) name, or a custom-id ref for a typed-in name.
    var placeForRecord: WidgetPlaceRef? {
        let name = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let placeRef, !PostcardCopy.isCustom(placeRef) {
            return WidgetPlaceRef(id: placeRef.id, name: name, city: placeRef.city, isGlobal: placeRef.isGlobal)
        }
        return WidgetPlaceRef(id: PostcardCopy.customPlaceId, name: name, city: nil, isGlobal: false)
    }

    /// Only real FavCircles places cross the host boundary.
    var placeForHost: WidgetPlaceRef? {
        guard let place = placeForRecord, !PostcardCopy.isCustom(place) else { return nil }
        return place
    }

    // MARK: - Sections

    // MARK: - Seeding & draft

    // MARK: - Send

    // MARK: - Mail a printed card

}

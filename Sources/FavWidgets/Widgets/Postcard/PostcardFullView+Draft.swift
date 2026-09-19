import SwiftUI
import PhotosUI
import FavWidgetsCore

extension PostcardFullView {
    func seed() async {
        await settings.loadIfNeeded()

        // Read before the once-only guard below. The host can hand us a photo
        // on any visit — a second Moment sent as a postcard — and that has to
        // land even when the rest of the draft is already seeded. Cleared as
        // it is read so the photo is used exactly once.
        let launch = context.launchPhoto
        context.launchPhoto = nil
        if let launch {
            photo = launch.image
            // A new photo means a new card, not the receipt from the last one.
            sentRecord = nil
        }

        let isFirstSeed = !hasSeeded
        if isFirstSeed {
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
        }

        if let place = launch?.place {
            // Where the photo was taken beats both a saved draft and a guess
            // from wherever the phone happens to be now.
            placeRef = place
            placeName = place.name
        } else if isFirstSeed, placeRef == nil, let nearby = await context.host.nearbyOrCurrentPlace() {
            placeRef = nearby
            if placeName.isEmpty { placeName = nearby.name }
        }
    }

    func persistDraft() {
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

    func loadPhoto(from item: PhotosPickerItem) async {
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

    /// Re-checks the address a beat after typing stops. The check is metered
    /// on the vendor's side, so it runs once per settled address rather than
    /// once per keystroke.
    func scheduleQuote() {
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
    func schedulePrintUpload() {
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

    /// Clears everything except the place (the user is still on the same
    /// trip) and the template.
    func resetCompose() {
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

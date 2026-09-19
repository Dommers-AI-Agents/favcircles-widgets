import SwiftUI
import PhotosUI
import FavWidgetsCore

extension PostcardFullView {
    /// Accepting the correction means writing it into the form. The fields
    /// then show what will actually print, the re-check comes back matching,
    /// and there's no separate "confirmed" state to get out of sync.
    func acceptMailCorrection() {
        guard let quote = mailQuote else { return }
        mailAddress = applyingName(quote.address)
    }

    /// Renders the postcard, publishes a public page for it, and hands the
    /// image plus a link to the share sheet. Non-users open the link in a
    /// browser and see the card with the FavCircles pitch underneath. If
    /// the page can't be made, the image still goes out.
    func share() {
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

    func shareCard(jpeg: Data, note: String, link: URL?) {
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

    /// One Send, every selected route: in-app to a connection, email to
    /// typed addresses, then optionally the share sheet. Each route records
    /// its own history entry; a failure in one doesn't undo the others.
    func send() async {
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

    func loadMailConfig() async {
        guard mailConfig == nil else { return }
        // A failure here just means no paid option this session. It is never
        // worth an alert: every free route still works.
        mailConfig = try? await PostcardMail.config(context: context)
    }

    /// Runs the paid leg. Returns the order, or nil when the person dismissed
    /// the wallet or something went wrong — the caller treats nil as "don't
    /// send the free routes either", because a card that says it's in the
    /// mail must not go out before the mail is paid for.
    func mailPrintedCard(message: String, place: WidgetPlaceRef?) async -> Result<PostcardMailOrder?, Error> {
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
    func cancelMail(_ order: PostcardMailOrder) async {
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
    func updateStoredMailOrder(_ order: PostcardMailOrder) {
        context.month(PostcardMonth.self, context.currentMonth).update { month in
            for index in month.sent.indices where month.sent[index].mailOrder?.orderId == order.orderId {
                month.sent[index].mailOrder = order
            }
        }
    }

    /// The postal service standardizes the street but doesn't know the
    /// person's name, so keep the typed one.
    func applyingName(_ standardized: PostcardMailAddress) -> PostcardMailAddress {
        var address = standardized
        address.name = mailAddress.normalized.name
        return address
    }
}

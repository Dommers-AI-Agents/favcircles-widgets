import SwiftUI
import PhotosUI
import FavWidgetsCore

extension PostcardFullView {
    /// Says which thing is missing, rather than leaving a disabled button
    /// with no explanation.
    /// Why Send is off, named precisely enough to act on.
    ///
    /// A greyed-out button with no reason is indistinguishable from a broken
    /// one — App Review rejected a build for exactly that. Every branch here
    /// has to name the field or the choice, never "fill in the form".
    var sendHint: String {
        if photo == nil { return "Add a photo to send." }
        if emailAddresses.valid.count > PostcardEmail.maxAddresses {
            return "Up to \(PostcardEmail.maxAddresses) email addresses at a time."
        }
        if let bad = emailAddresses.invalid.first {
            return "\(bad) doesn't look like an email address."
        }
        if mailOn && mailAvailable {
            if mailMessageTooLong { return "Shorten your message to mail a printed card." }
            // The specific field, not "the mailing address" — every box can be
            // full and one of them still wrong.
            if let problem = mailAddress.firstProblem { return problem }
            if isQuoting { return "Checking the mailing address…" }
            // A failed CHECK is not a pending one. Without this the hint reads
            // "Checking the mailing address…" forever behind a button that will
            // never enable — the same dead end that got 1.3.3 rejected.
            if let failure = mailQuoteError {
                return "We couldn't check that address: \(failure)"
            }
            if mailQuote?.deliverable == false { return "We couldn't find that address. Check the street, city, state and ZIP." }
            if mailCorrectionPending { return "Check the corrected address above before sending." }
            if mailQuote == nil { return "Checking the mailing address…" }
        }
        return "Choose a connection and/or enter an email, or just share the card."
    }

    func sendSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.primaryButton("Send postcard", color: context.accent) {
                Task { await send() }
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
            // Shown whenever Send is off, for ANY reason. It used to appear
            // only when the photo or the recipient was missing, so a bad email
            // or an unmailable address left a dead button explaining nothing.
            if !canSend {
                Text(sendHint)
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

    func sentPanel(_ record: PostcardRecord, theme: WidgetTheme) -> some View {
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

    func historySection(_ theme: WidgetTheme) -> some View {
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

    func sendingOverlay(_ theme: WidgetTheme) -> some View {
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

    func secondaryLabel(_ title: String, symbol: String, theme: WidgetTheme) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(context.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(context.accent.opacity(0.12)))
    }
}

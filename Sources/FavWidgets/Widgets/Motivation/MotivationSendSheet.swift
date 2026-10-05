import SwiftUI
import FavWidgetsCore

/// "Send to someone who needs to hear this": Coach Mane's card to a
/// FavCircles friend's chat, or anywhere through the share sheet. A private
/// message — never a feed post.
struct MotivationSendSheet: View {
    let context: WidgetContext
    let line: String
    /// "push" (the notification's Send action) or "page", for analytics.
    let source: String

    @Environment(\.dismiss) private var dismiss
    @State private var recipient: WidgetContact?
    @State private var choosingRecipient = false
    @State private var isSending = false

    private struct SendResponse: Decodable { let success: Bool }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Send to someone", theme: theme,
                    confirm: (label: isSending ? "Sending…" : "Send", enabled: recipient != nil && !isSending, action: send),
                    cancelDisabled: isSending) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Who needs to hear this?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)

                    Button { choosingRecipient = true } label: {
                        HStack {
                            Text("To").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            Text(recipient?.displayName ?? "Choose a FavCircles friend")
                                .font(.system(size: 16)).foregroundStyle(recipient == nil ? context.accent : theme.label)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.secondaryBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)

                    Button(action: shareAnywhere) {
                        Label("Share anywhere…", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.tertiaryBackground))
                            .foregroundStyle(theme.label)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityHint("Messages, WhatsApp, Instagram and more")

                    MotivationShareCard(line: line, accent: context.accent)
                        .scaleEffect(0.82, anchor: .top)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Card: Coach Mane says \(line)")
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $choosingRecipient) {
            PostcardRecipientPicker(context: context, selectedId: recipient?.id) { contact in
                recipient = contact
                choosingRecipient = false
            }
        }
    }

    /// The card alone, as one tappable bubble (WidgetShareCard).
    private func shareAnywhere() {
        context.track("motivation_shared", ["from": source])
        context.host.share(WidgetShareCard.items(widgetId: "motivation", title: MotivationShareText.shareTitle,
                                                 cardJPEG: MotivationShareCard.jpeg(line: line, accent: context.accent),
                                                 fallbackText: MotivationShareText.shareText(line: line)))
    }

    private func send() {
        guard let recipient, !isSending else { return }
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                guard let jpeg = MotivationShareCard.jpeg(line: line, accent: context.accent) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let imageURL = try await context.host.uploadImage(jpeg)
                let body: [String: Any] = [
                    "recipientId": recipient.id,
                    "lineId": MotivationLines.id(for: line),
                    "line": String(line.prefix(MotivationShareText.lineLimit)),
                    "imageUrl": imageURL.absoluteString
                ]
                let _: SendResponse = try await context.api(.post, "widgets/motivation/send", body: body)
                context.host.haptic(.success)
                context.track("motivation_sent", ["from": source])
                context.host.presentAlert(WidgetAlert(
                    title: "Sent", message: MotivationShareText.sentConfirmation(recipientName: recipient.displayName)))
                dismiss()
            } catch {
                context.host.haptic(.warning)
                context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: "Check your connection and try again."))
            }
        }
    }
}

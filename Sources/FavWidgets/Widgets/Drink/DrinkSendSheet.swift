import SwiftUI
import FavWidgetsCore

/// "Send to a friend": pick a connection, add a note, and the recipe card
/// arrives in their chat. A private message — never a feed post. The
/// recipient may get a FavCoin from FavCircles (the server decides; never
/// the sender's coins).
struct DrinkSendSheet: View {
    let context: WidgetContext
    let drink: Cocktail

    @Environment(\.dismiss) private var dismiss
    @State private var recipient: WidgetContact?
    @State private var note = ""
    @State private var choosingRecipient = false
    @State private var isSending = false

    private struct SendResponse: Decodable {
        let success: Bool
        let recipientCredited: Bool?
    }

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Send a drink", theme: theme,
                    confirm: (label: isSending ? "Sending…" : "Send", enabled: recipient != nil && !isSending, action: send),
                    cancelDisabled: isSending) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button { choosingRecipient = true } label: {
                        HStack {
                            Text("To").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            Text(recipient?.displayName ?? "Choose a friend")
                                .font(.system(size: 16)).foregroundStyle(recipient == nil ? context.accent : theme.label)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.secondaryBackground))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Add a note (optional)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.secondaryBackground))
                        Text("\(note.count)/\(DrinkShareText.noteLimit)")
                            .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    }

                    DrinkShareCard(drink: drink, accent: context.accent)
                        .scaleEffect(0.82, anchor: .top)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
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
        .onChange(of: note) { value in
            if value.count > DrinkShareText.noteLimit { note = String(value.prefix(DrinkShareText.noteLimit)) }
        }
    }

    private func send() {
        guard let recipient, !isSending else { return }
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                guard let jpeg = DrinkShareCard.jpeg(drink: drink, accent: context.accent) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let imageURL = try await context.host.uploadImage(jpeg)
                var body: [String: Any] = [
                    "recipientId": recipient.id, "drinkId": drink.id,
                    "drinkName": drink.name, "imageUrl": imageURL.absoluteString
                ]
                if let clean = DrinkShareText.cleanNote(note) { body["note"] = clean }
                let response: SendResponse = try await context.api(.post, "widgets/drink/send", body: body)
                context.host.haptic(.success)
                context.track("drink_sent", ["credited": (response.recipientCredited ?? false) ? "1" : "0"])
                context.host.presentAlert(WidgetAlert(
                    title: "Sent",
                    message: DrinkShareText.sentConfirmation(drinkName: drink.name, recipientName: recipient.displayName,
                                                             recipientCredited: response.recipientCredited ?? false)))
                dismiss()
            } catch {
                context.host.haptic(.warning)
                context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: "Check your connection and try again."))
            }
        }
    }
}

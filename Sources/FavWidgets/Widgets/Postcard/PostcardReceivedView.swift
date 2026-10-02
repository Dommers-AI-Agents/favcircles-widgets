import SwiftUI
import FavWidgetsCore

/// A postcard someone received, opened in the app from the printed card's QR
/// or the web page's "Open it in the app": the card, the note, who sent it,
/// and "Send one back" (or "Send another" when it's your own card).
struct PostcardReceivedView: View {
    let context: WidgetContext
    let token: String
    /// Called with the card when they choose to send one; the page closes
    /// this sheet and readies the composer.
    let onSendBack: (ReceivedPostcard) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var card: ReceivedPostcard?
    @State private var failed: String?
    @State private var showFullSize = false

    private struct Response: Decodable { let postcard: ReceivedPostcard }

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let card {
                        loaded(card, theme: theme)
                    } else if let failed {
                        VStack(spacing: 12) {
                            Image(systemName: "envelope.badge").font(.system(size: 36)).foregroundStyle(theme.secondaryLabel)
                            Text(failed).font(.system(size: 16)).foregroundStyle(theme.label).multilineTextAlignment(.center)
                            Button("Try again") { Task { await load() } }
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                        }
                        .padding(.top, 60)
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(card.map(ReceivedPostcardCopy.title) ?? "Postcard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func loaded(_ card: ReceivedPostcard, theme: WidgetTheme) -> some View {
        Button { showFullSize = true } label: {
            AsyncImage(url: URL(string: card.imageUrl)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: Color.gray.opacity(0.2).aspectRatio(1.5, contentMode: .fit)
                default: ProgressView().frame(maxWidth: .infinity).aspectRatio(1.5, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Postcard image. Double-tap to view full size.")

        if !card.message.isEmpty {
            Text(card.message)
                .font(.system(size: 20))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: 4) {
            Text(ReceivedPostcardCopy.byline(card)).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            if let place = ReceivedPostcardCopy.place(card) {
                Text(place).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
            }
        }

        VStack(spacing: 8) {
            WidgetUI.primaryButton(ReceivedPostcardCopy.primaryButton(card), color: context.accent) {
                context.track("postcard_received_send_back", ["mine": card.isMine ? "1" : "0",
                                                              "connected": card.senderIsConnection ? "1" : "0"])
                onSendBack(card)
                dismiss()
            }
            Text(ReceivedPostcardCopy.sendHint(card))
                .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .sheet(isPresented: $showFullSize) {
            NavigationStack {
                AsyncImage(url: URL(string: card.imageUrl)) { image in
                    image.resizable().scaledToFit()
                } placeholder: { ProgressView() }
                .padding()
                .background(Color.black.ignoresSafeArea())
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showFullSize = false } } }
            }
        }
    }

    private func load() async {
        failed = nil
        do {
            let response: Response = try await context.api(.get, "widgets/postcard/share/\(token)")
            card = response.postcard
            context.track("postcard_received_opened", ["mine": response.postcard.isMine ? "1" : "0"])
        } catch {
            failed = "Couldn't open this postcard. Check your connection and try again."
        }
    }
}

import SwiftUI
import FavWidgetsCore

/// A mailed card, full size (Wes, 2026-10-14): the front as it printed, to
/// pinch and zoom, with who it went to, the message on the back, when it
/// was mailed and where it is. Save to Photos and Share hand over the card
/// image.
struct FridgeMailCardDetailView: View {
    let context: WidgetContext
    let card: FridgeMailCard
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZoomableRemoteImage(url: card.imageURL)
                        .aspectRatio(1.5, contentMode: .fit)
                        .background(FridgeMailCanvasView.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .accessibilityLabel("The card's front, as printed. Pinch or double-tap to zoom.")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                        Text(FridgeMailCopy.cardStatus(card.status, recipientName: card.recipientName,
                                                       printerHold: card.printerHold == true, outForDelivery: card.isOutForDelivery))
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        Text("Mailed \(card.createdAt.formatted(date: .long, time: .omitted))")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }

                    if !card.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            WidgetUI.header("Message on the back", theme: theme)
                            Text(card.note).font(.system(size: 15)).foregroundStyle(theme.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(card.childName.isEmpty ? "Card" : card.childName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await save() } } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Save card to Photos")
                    Button { Task { await share() } } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share card")
                }
            }
            .disabled(busy || card.imageURL == nil)
        }
    }

    private var title: String {
        card.childName.isEmpty ? "To \(card.recipientName ?? "Grandma")" : "\(card.childName) → \(card.recipientName ?? "Grandma")"
    }

    private func imageData() async -> Data? {
        guard let url = card.imageURL, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        return data
    }

    private func save() async {
        busy = true
        defer { busy = false }
        guard let data = await imageData() else {
            return context.host.presentAlert(WidgetAlert(title: "Couldn't download the card", message: "Check your connection and try again."))
        }
        do {
            try await context.host.saveImageToPhotos(data)
            context.host.haptic(.success)
            context.track("fridgemail_card_saved")
            context.host.presentAlert(WidgetAlert(title: "Saved", message: "The card is in your Photos."))
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't save to Photos", message: "Allow FavCircles to add photos in Settings, then try again."))
        }
    }

    private func share() async {
        busy = true
        defer { busy = false }
        guard let data = await imageData() else {
            return context.host.presentAlert(WidgetAlert(title: "Couldn't download the card", message: "Check your connection and try again."))
        }
        context.track("fridgemail_card_shared")
        context.host.share([.imageJPEG(data)])
    }
}

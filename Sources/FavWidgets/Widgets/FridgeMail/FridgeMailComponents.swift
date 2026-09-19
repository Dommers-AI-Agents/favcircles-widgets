import SwiftUI
import PhotosUI
import FavWidgetsCore

/// A small server image with the cream card behind it while it loads.
struct FridgeMailThumb: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        WidgetUI.thumbnail(url: url, width: width, height: height, background: FridgeMailCanvasView.cream)
    }
}

/// Front and back of the card that goes out next, as it will print.
struct FridgeMailPreview: View {
    let item: FridgeMailQueueItem
    let familyName: String
    let calendar: Calendar

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: item.imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    ZStack {
                        FridgeMailCanvasView.cream
                        ProgressView().controlSize(.small)
                    }
                    .aspectRatio(1.5, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)

            VStack(spacing: 6) {
                Text(FridgeMailCopy.backHeadline(childName: item.childName, ageText: item.ageText, date: Date(), calendar: calendar))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if !item.note.isEmpty {
                    Text(item.note).font(.system(size: 13)).multilineTextAlignment(.center)
                }
                Text(FridgeMailCopy.signature(familyName: familyName)).font(.system(size: 13, design: .serif)).italic()
            }
            .foregroundStyle(FridgeMailCanvasView.ink)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FridgeMailCanvasView.frame.opacity(0.4), lineWidth: 1))
        }
    }
}

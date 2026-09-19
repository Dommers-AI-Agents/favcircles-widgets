import SwiftUI
import PhotosUI
import FavWidgetsCore

/// A small photo of the exercise (the machine's placard), or a symbol
/// when the person hasn't attached one.
struct ExerciseThumb: View {
    let url: URL?
    let symbolName: String
    let accent: Color
    let theme: WidgetTheme
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.12))
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Image(systemName: symbolName).foregroundStyle(accent) }
                }
            } else {
                Image(systemName: symbolName).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

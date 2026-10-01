import SwiftUI
import FavWidgetsCore

/// A drink recipe drawn as a card: for the share sheet, and the image a sent
/// drink arrives as in the friend's chat.
struct DrinkShareCard: View {
    let drink: Cocktail
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(drink.base.label) · \(drink.style.label)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Text(drink.name).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    if let calories = DrinkCalories.label(drink) {
                        Text(calories).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Text(drink.base.emoji).font(.system(size: 36))
            }
            Text(drink.blurb).font(.system(size: 15)).foregroundStyle(.white.opacity(0.92))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(drink.ingredients, id: \.self) { ingredient in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ingredient.amount.isEmpty ? "•" : ingredient.amount)
                            .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(minWidth: 56, alignment: .leading)
                        Text(ingredient.item).font(.system(size: 15)).foregroundStyle(.white)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)))
            HStack(spacing: 14) {
                Label(drink.glass, systemImage: "wineglass")
                Label(drink.garnish, systemImage: "leaf")
            }
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            Text("Make Me a Drink · FavCircles").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(22)
        .frame(width: 400, alignment: .leading)
        .background(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    @MainActor
    static func jpeg(drink: Cocktail, accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: DrinkShareCard(drink: drink, accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}

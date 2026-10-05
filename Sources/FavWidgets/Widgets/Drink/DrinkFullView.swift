import SwiftUI
import FavWidgetsCore

struct DrinkFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<DrinkSettings>
    @State private var query = ""
    @State private var shown: Cocktail?
    @State private var shakeCount = 0
    @State private var sending: Cocktail?

    private var results: [Cocktail] { DrinkPicker.search(query) }

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchField
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResults
                } else {
                    baseChips
                    if let drink = shown ?? state.model.currentPick {
                        DrinkRecipeView(context: context, drink: drink,
                                        isFavorite: state.model.favoriteIds.contains(drink.id),
                                        onFavorite: {
                                            context.host.haptic(.selection)
                                            state.update { $0.toggleFavorite(drink.id) }
                                        },
                                        onSend: { sending = drink },
                                        onShare: { share(drink) })
                        .id("\(drink.id)-\(shakeCount)")
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                    }
                    WidgetUI.primaryButton(shakeTitle, color: context.accent) { surprise() }
                    favoritesSection
                }
                Text("Please drink responsibly · 21+ · Never drink and drive.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(theme.background)
        .task {
            await state.loadIfNeeded()
            // A drink a friend sent, tapped in chat: open that recipe
            if let launched = context.launchDrinkId {
                context.launchDrinkId = nil
                if let drink = CocktailLibrary.cocktail(id: launched) { shown = drink; return }
            }
            if state.model.currentPickId == nil { state.shake() }
        }
        .sheet(item: $sending) { drink in
            DrinkSendSheet(context: context, drink: drink)
        }
    }

    /// The recipe card (it lists the ingredients) as one tappable bubble.
    /// Private by nature: nothing is posted anywhere.
    private func share(_ drink: Cocktail) {
        context.track("drink_shared")
        context.host.share(WidgetShareCard.items(widgetId: "drink", title: "\(drink.name) · Make Me a Drink",
                                                 cardJPEG: DrinkShareCard.jpeg(drink: drink, accent: context.accent),
                                                 fallbackText: DrinkShareText.shareText(drink)))
    }

    private var shakeTitle: String {
        if let base = state.model.baseFilter { return "Surprise me with \(base.label.lowercased())" }
        return "Surprise me"
    }

    // MARK: - Search

    private var searchField: some View {
        let theme = context.theme
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryLabel)
            TextField("How do I make a… (Manhattan, sour, tiki)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(theme.label)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryLabel) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private var searchResults: some View {
        let theme = context.theme
        let found = results
        return VStack(alignment: .leading, spacing: 10) {
            if found.isEmpty {
                Text("No drink called \"\(query)\" yet. Try a classic like Manhattan, Margarita or Mojito, or a style like sour or tiki.")
                    .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            } else if found.count == 1, let only = found.first {
                DrinkRecipeView(context: context, drink: only, isFavorite: state.model.favoriteIds.contains(only.id),
                                onFavorite: { state.update { $0.toggleFavorite(only.id) } },
                                onSend: { sending = only },
                                onShare: { share(only) })
            } else {
                WidgetUI.header("\(found.count) drinks", theme: theme)
                ForEach(found) { drink in
                    Button {
                        context.track("drink_open_recipe", ["id": drink.id])
                        query = ""
                        withAnimation(.spring(response: 0.35)) { shown = drink }
                    } label: { DrinkRow(context: context, drink: drink) }
                        .buttonStyle(.plain)
                    Divider().overlay(theme.separator)
                }
            }
        }
    }

    // MARK: - Base spirit

    private var baseChips: some View {
        let theme = context.theme
        let bases: [SpiritBase?] = [nil, .vodka, .tequila, .gin, .rum, .whiskey, .mezcal, .brandy, .bubbly, .liqueur, .zeroProof]
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("What are you in the mood for?", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bases, id: \.self) { base in
                        let selected = state.model.baseFilter == base
                        Button {
                            context.host.haptic(.selection)
                            state.update { $0.baseFilter = base }
                            surprise()
                        } label: {
                            Text(base.map { "\($0.emoji) \($0.label)" } ?? "🎲 Anything")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selected ? .white : theme.label)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(selected ? context.accent : theme.secondaryBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Favorites

    @ViewBuilder
    private var favoritesSection: some View {
        let theme = context.theme
        let favorites = state.model.favoriteIds.compactMap(CocktailLibrary.cocktail(id:))
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.header("Your favorites", theme: theme)
                ForEach(favorites) { drink in
                    Button { withAnimation(.spring(response: 0.35)) { shown = drink } } label: { DrinkRow(context: context, drink: drink) }
                        .buttonStyle(.plain)
                    Divider().overlay(theme.separator)
                }
            }
        }
    }

    private func surprise() {
        context.track("drink_surprise", ["base": state.model.baseFilter?.rawValue ?? "any"])
        context.host.haptic(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            shown = nil
            state.shake()
            shakeCount += 1
        }
    }
}

struct DrinkRow: View {
    let context: WidgetContext
    let drink: Cocktail

    var body: some View {
        let theme = context.theme
        HStack(spacing: 12) {
            Text(drink.base.emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(drink.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                Text("\(drink.base.label) · \(drink.style.label)").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// The big card: what it is, how to order it, and how to make it.
struct DrinkRecipeView: View {
    let context: WidgetContext
    let drink: Cocktail
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onSend: () -> Void
    let onShare: () -> Void

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(drink.base.emoji) \(drink.base.label) · \(drink.style.label) · \(strength)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(context.accent)
                    Text(drink.name).font(.system(size: 28, weight: .bold)).foregroundStyle(theme.label)
                    if let calories = DrinkCalories.label(drink) {
                        Text("\(calories) · estimate")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryLabel)
                            .accessibilityLabel("About \(DrinkCalories.estimate(drink) ?? 0) calories, estimated from the recipe")
                    }
                }
                Spacer()
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(isFavorite ? context.accent : theme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            Text(drink.blurb).font(.system(size: 15)).foregroundStyle(theme.label)
            Label(drink.orderTip, systemImage: "text.bubble.fill")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)

            Divider().overlay(theme.separator)
            HStack(alignment: .firstTextBaseline) {
                Text("How to make it").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.secondaryLabel).textCase(.uppercase)
                Spacer()
                Text("Measures in oz unless noted").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(drink.ingredients, id: \.self) { ingredient in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ingredient.amount.isEmpty ? "•" : ingredient.amount)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(context.accent)
                            .frame(minWidth: 64, alignment: .leading)
                        Text(ingredient.item).font(.system(size: 15)).foregroundStyle(theme.label)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(drink.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.secondaryLabel)
                        Text(step).font(.system(size: 15)).foregroundStyle(theme.label)
                    }
                }
            }
            HStack(spacing: 16) {
                Label(drink.glass, systemImage: "wineglass").font(.system(size: 13))
                Label(drink.garnish, systemImage: "leaf").font(.system(size: 13))
            }
            .foregroundStyle(theme.secondaryLabel)
            HStack(spacing: 10) {
                actionButton("Send to a friend", systemImage: "paperplane.fill", filled: true, action: onSend)
                actionButton("Share", systemImage: "square.and.arrow.up", filled: false, action: onShare)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.secondaryBackground))
    }

    private func actionButton(_ title: String, systemImage: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(filled ? .white : context.accent)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filled ? context.accent : context.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var strength: String {
        switch drink.strength {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

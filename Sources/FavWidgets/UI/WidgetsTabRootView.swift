import SwiftUI
import FavWidgetsCore

/// The scrolling list of widget cards the app hosts in the home tab.
public struct WidgetsTabRootView: View {
    @ObservedObject var model: WidgetsTabModel

    public init(model: WidgetsTabModel) {
        self.model = model
    }

    public var body: some View {
        let theme = model.theme
        ZStack {
            theme.background.ignoresSafeArea()
            // A List (not a ScrollView) so the cards can be reordered in
            // place: press and hold a card, then drag. Rows are styled flat
            // so it still reads as the card stack it was.
            List {
                Group {
                    header
                        .moveDisabled(true)
                    if model.hasLoaded && model.visible.isEmpty {
                        WidgetStatusView(theme: theme, isLoading: false,
                                         message: "All widgets are off — tap Manage to turn some on")
                            .frame(height: 160)
                            .moveDisabled(true)
                    }
                    ForEach(model.visible) { descriptor in
                        if let widget = model.widget(for: descriptor) {
                            widget.makeCardView(context: model.context(for: descriptor))
                                .id(descriptor.id)
                        }
                    }
                    .onMove { source, destination in
                        model.moveVisible(from: source, to: destination)
                        model.host.haptic(.light)
                    }
                    if let error = model.loadError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryLabel)
                            .padding(.top, 4)
                            .moveDisabled(true)
                    }
                    Color.clear.frame(height: 24)
                        .moveDisabled(true)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            if model.isLoading && !model.hasLoaded {
                WidgetStatusView(theme: theme, isLoading: true, message: nil)
            }
        }
        .task { await model.loadIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text("Your widgets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.theme.secondaryLabel)
            Spacer()
            Button("Manage") { model.onManage() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.theme.primary)
        }
        .padding(.top, 4)
    }
}

/// Loading card / empty message, matching the UIKit `HomeTabStatusView`.
public struct WidgetStatusView: View {
    let theme: WidgetTheme
    let isLoading: Bool
    let message: String?

    public init(theme: WidgetTheme, isLoading: Bool, message: String?) {
        self.theme = theme
        self.isLoading = isLoading
        self.message = message
    }

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(theme.primary)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.background.opacity(0.95))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
            } else if let message {
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

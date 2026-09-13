import SwiftUI
import FavWidgetsCore

/// The card chrome every widget renders inside on the tab: accent symbol
/// tile, title, the widget's own summary content, and an optional quick
/// action. Tapping anywhere else opens the full view.
public struct WidgetCard<Content: View>: View {
    let context: WidgetContext
    let action: WidgetQuickAction?
    let content: () -> Content

    public init(context: WidgetContext, action: WidgetQuickAction? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.context = context
        self.action = action
        self.content = content
    }

    public var body: some View {
        let theme = context.theme
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(context.accent.opacity(0.18))
                Image(systemName: context.descriptor.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(context.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.descriptor.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.label)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action {
                WidgetQuickActionButton(action: action, theme: theme, accent: context.accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(theme.secondaryBackground)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            context.track("widget_opened")
            context.openFullView()
        }
        .accessibilityElement(children: .contain)
    }
}

/// A card's one-tap action ("+ Cup", "Start workout").
public struct WidgetQuickAction {
    public let title: String
    public let symbolName: String?
    public let handler: () -> Void

    public init(_ title: String, symbolName: String? = nil, handler: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.handler = handler
    }
}

struct WidgetQuickActionButton: View {
    let action: WidgetQuickAction
    let theme: WidgetTheme
    let accent: Color

    var body: some View {
        Button(action: action.handler) {
            HStack(spacing: 4) {
                if let symbolName = action.symbolName {
                    Image(systemName: symbolName).font(.system(size: 12, weight: .bold))
                }
                Text(action.title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(accent))
        }
        .buttonStyle(.plain)
    }
}

/// Shared small pieces so widgets look like one family.
public enum WidgetUI {
    public static func summary(_ text: String, theme: WidgetTheme) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(theme.secondaryLabel)
            .lineLimit(2)
    }

    /// A thin progress bar for goals.
    public static func progressBar(fraction: Double, color: Color, theme: WidgetTheme) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.tertiaryBackground)
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: 6)
    }

    /// Section header used inside full views.
    public static func header(_ text: String, theme: WidgetTheme) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full-width primary button used inside full views.
    public static func primaryButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
        }
        .buttonStyle(.plain)
    }
}

/// Small sync badge shown on full views; quiet unless something is wrong.
public struct WidgetSyncBadge: View {
    let state: WidgetSyncState
    let theme: WidgetTheme

    public init(state: WidgetSyncState, theme: WidgetTheme) {
        self.state = state
        self.theme = theme
    }

    public var body: some View {
        switch state {
        case .idle, .loading, .saving:
            EmptyView()
        case .error(let message):
            Label(message, systemImage: "exclamationmark.icloud")
                .font(.system(size: 12))
                .foregroundStyle(theme.warning)
        case .conflict:
            Label("Updated on another device — pull to refresh", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(theme.warning)
        }
    }
}

// Keyboard modifiers are iOS-only; these keep the macOS (`swift test`)
// build compiling without sprinkling #if through every form.
public extension View {
    @ViewBuilder
    func widgetDecimalKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func widgetNumberKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func widgetInlineNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        self.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        #else
        self.navigationTitle(title)
        #endif
    }
}

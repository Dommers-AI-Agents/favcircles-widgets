import SwiftUI

/// Colors and metrics the widgets draw with. The app builds one from its
/// own `Constants.Colors` so the tab matches the rest of FavCircles; the
/// default uses system colors so previews and tests look right too.
public struct WidgetTheme: Sendable {
    public var primary: Color
    public var accent: Color
    public var background: Color
    public var secondaryBackground: Color
    public var tertiaryBackground: Color
    public var label: Color
    public var secondaryLabel: Color
    public var separator: Color
    public var success: Color
    public var warning: Color
    public var danger: Color
    public var cardCornerRadius: CGFloat

    public init(
        primary: Color,
        accent: Color,
        background: Color,
        secondaryBackground: Color,
        tertiaryBackground: Color,
        label: Color,
        secondaryLabel: Color,
        separator: Color,
        success: Color,
        warning: Color,
        danger: Color,
        cardCornerRadius: CGFloat = 12
    ) {
        self.primary = primary
        self.accent = accent
        self.background = background
        self.secondaryBackground = secondaryBackground
        self.tertiaryBackground = tertiaryBackground
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.separator = separator
        self.success = success
        self.warning = warning
        self.danger = danger
        self.cardCornerRadius = cardCornerRadius
    }

    public static let `default`: WidgetTheme = {
        #if canImport(UIKit)
        return WidgetTheme(
            primary: Color(red: 0.19, green: 0.51, blue: 0.81),      // #3182CE
            accent: Color(red: 0.31, green: 0.82, blue: 0.77),       // #4FD1C5
            background: Color(uiColor: .systemBackground),
            secondaryBackground: Color(uiColor: .secondarySystemBackground),
            tertiaryBackground: Color(uiColor: .tertiarySystemBackground),
            label: Color(uiColor: .label),
            secondaryLabel: Color(uiColor: .secondaryLabel),
            separator: Color(uiColor: .separator),
            success: Color(red: 0.22, green: 0.63, blue: 0.41),
            warning: Color(red: 0.93, green: 0.79, blue: 0.29),
            danger: Color(red: 0.90, green: 0.24, blue: 0.24)
        )
        #else
        return WidgetTheme(
            primary: Color(red: 0.19, green: 0.51, blue: 0.81),
            accent: Color(red: 0.31, green: 0.82, blue: 0.77),
            background: Color.white,
            secondaryBackground: Color.gray.opacity(0.12),
            tertiaryBackground: Color.gray.opacity(0.2),
            label: Color.primary,
            secondaryLabel: Color.secondary,
            separator: Color.gray.opacity(0.3),
            success: Color.green,
            warning: Color.yellow,
            danger: Color.red
        )
        #endif
    }()
}

public extension Color {
    /// "#RRGGBB" → Color; falls back to gray on bad input.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

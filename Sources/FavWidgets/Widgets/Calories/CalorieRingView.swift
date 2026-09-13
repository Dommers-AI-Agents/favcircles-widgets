import SwiftUI
import FavWidgetsCore

/// Progress ring with the kcal number in the middle. Turns to the warning
/// color once the goal is passed.
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int
    let theme: WidgetTheme
    let accent: Color
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(consumed) / Double(goal))
    }

    private var isOver: Bool { goal > 0 && consumed > goal }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.tertiaryBackground, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isOver ? theme.warning : accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
            Text(CalorieFormat.kcal(consumed))
                .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(lineWidth + 2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(consumed) of \(goal) calories")
    }
}

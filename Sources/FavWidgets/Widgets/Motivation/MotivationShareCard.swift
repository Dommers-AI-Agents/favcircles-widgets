import SwiftUI
import FavWidgetsCore

/// Coach Mane yelling one line, drawn as a card: what the share sheet sends
/// and what a FavCircles friend gets in their chat.
struct MotivationShareCard: View {
    let line: String
    let accent: Color

    /// A frame with his mouth wide open (jaw ≈ 1, barely any head shake).
    static let shoutFrame = 0.714

    var body: some View {
        VStack(spacing: 14) {
            Text(line)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
                .overlay(alignment: .bottom) {
                    // The bubble's tail, pointing down at the coach.
                    Triangle().fill(.white)
                        .frame(width: 26, height: 16)
                        .offset(y: 15)
                }
            CoachView(shouting: true, size: 170).figure(t: Self.shoutFrame)
                .frame(width: 170, height: 170)
            VStack(spacing: 4) {
                Text(MotivationShareText.cardCaption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Coach Mane · FavCircles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(LinearGradient(colors: [accent, Color(red: 0.35, green: 0.05, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom))
    }

    @MainActor
    static func jpeg(line: String, accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: MotivationShareCard(line: line, accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

import SwiftUI

/// Coach Mane: an original, drawn long-haired coach with a headband and a
/// beard who shouts at you. Hair swings, jaw flaps, head shakes while
/// `shouting`; idle he just breathes. Pure SwiftUI shapes — no assets.
struct CoachView: View {
    var shouting: Bool = true
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            figure(t: t)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(shouting ? "Coach Mane, shouting" : "Coach Mane")
    }

    private func figure(t: Double) -> some View {
        let s = size / 120
        // Shout: fast jaw + a head shake that comes in bursts.
        let burst = shouting ? max(0, sin(t * 2.2)) : 0
        let jaw = shouting ? (0.35 + 0.65 * abs(sin(t * 11))) * (0.4 + 0.6 * burst) : 0.08 + 0.04 * sin(t * 2)
        let shake = shouting ? sin(t * 18) * 3 * burst : 0
        let sway = sin(t * (shouting ? 5 : 1.6)) * (shouting ? 7 : 3)
        let breathe = 1 + 0.015 * sin(t * 2)

        return ZStack {
            // Hair behind the head: long strands that swing.
            ForEach(0..<7, id: \.self) { i in
                let x = CGFloat(i - 3) * 9 * s
                Capsule()
                    .fill(Self.hair)
                    .frame(width: 16 * s, height: (78 + CGFloat(abs(i - 3)) * -4) * s)
                    .rotationEffect(.degrees(sway * (0.6 + Double(abs(i - 3)) * 0.25) + Double(i - 3) * 9),
                                    anchor: .top)
                    .offset(x: x, y: 18 * s)
            }

            // Shoulders / tank top.
            RoundedRectangle(cornerRadius: 24 * s, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .frame(width: 104 * s, height: 40 * s)
                .offset(y: 46 * s)

            // Neck.
            Rectangle().fill(Self.skinShade)
                .frame(width: 22 * s, height: 16 * s)
                .offset(y: 30 * s)

            head(jaw: jaw, s: s)
                .rotationEffect(.degrees(shake))
                .offset(y: -6 * s)
        }
        .scaleEffect(breathe)
        .frame(width: size, height: size)
    }

    private func head(jaw: Double, s: CGFloat) -> some View {
        ZStack {
            // Face.
            Ellipse().fill(Self.skin)
                .frame(width: 58 * s, height: 68 * s)

            // Hair on top, parted, framing the face.
            Ellipse().fill(Self.hair)
                .frame(width: 66 * s, height: 34 * s)
                .offset(y: -28 * s)
            Capsule().fill(Self.hair)
                .frame(width: 12 * s, height: 50 * s)
                .offset(x: -30 * s, y: -2 * s)
            Capsule().fill(Self.hair)
                .frame(width: 12 * s, height: 50 * s)
                .offset(x: 30 * s, y: -2 * s)

            // Headband.
            Capsule().fill(Color.red)
                .frame(width: 64 * s, height: 8 * s)
                .offset(y: -18 * s)

            // Angry brows.
            Capsule().fill(Self.hair)
                .frame(width: 16 * s, height: 4 * s)
                .rotationEffect(.degrees(18))
                .offset(x: -11 * s, y: -8 * s)
            Capsule().fill(Self.hair)
                .frame(width: 16 * s, height: 4 * s)
                .rotationEffect(.degrees(-18))
                .offset(x: 11 * s, y: -8 * s)

            // Eyes.
            Circle().fill(Color.black).frame(width: 6 * s, height: 6 * s).offset(x: -11 * s, y: -1 * s)
            Circle().fill(Color.black).frame(width: 6 * s, height: 6 * s).offset(x: 11 * s, y: -1 * s)

            // Beard around the mouth; the jaw drops it.
            Ellipse().fill(Self.hair)
                .frame(width: 50 * s, height: (28 + 8 * jaw) * s)
                .offset(y: (24 + 3 * jaw) * s)

            // Mouth: dark, wide open when yelling, teeth on top.
            ZStack(alignment: .top) {
                Capsule().fill(Color(red: 0.35, green: 0.05, blue: 0.08))
                Rectangle().fill(Color.white)
                    .frame(height: 3 * s)
                    .padding(.horizontal, 3 * s)
                    .padding(.top, 1 * s)
                    .opacity(jaw > 0.25 ? 1 : 0)
            }
            .frame(width: (18 + 6 * jaw) * s, height: max(3, 22 * jaw) * s)
            .clipShape(Capsule())
            .offset(y: (17 + 5 * jaw) * s)
        }
    }

    static let skin = Color(red: 0.94, green: 0.76, blue: 0.62)
    static let skinShade = Color(red: 0.85, green: 0.66, blue: 0.53)
    static let hair = Color(red: 0.36, green: 0.22, blue: 0.12)
}

/// The coach with his line in a speech bubble above him.
struct CoachShoutView: View {
    let line: String
    var size: CGFloat = 140
    let accent: Color
    let theme: WidgetTheme

    @State private var popped = false

    var body: some View {
        VStack(spacing: 6) {
            Text(line)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.label)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.tertiaryBackground))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent, lineWidth: 2))
                .scaleEffect(popped ? 1 : 0.6)
                .opacity(popped ? 1 : 0)
                .id(line)
            CoachView(shouting: true, size: size)
        }
        .onAppear { pop() }
        .onChange(of: line) { _ in popped = false; pop() }
    }

    private func pop() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { popped = true }
    }
}

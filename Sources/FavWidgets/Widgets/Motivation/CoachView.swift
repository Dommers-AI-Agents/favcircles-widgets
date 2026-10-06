import SwiftUI

/// Coach Mane: an original, drawn long-haired coach with a headband and a
/// beard who shouts at you. Hair swings, jaw flaps, head shakes while
/// `shouting`; idle he just breathes. Pure SwiftUI shapes — no assets.
struct CoachView: View {
    var shouting: Bool = true
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Reduce Motion gets a calm coach (breathing, blinking) rather than
        // a frozen one — he used to stop dead and read as a still picture
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            figure(t: timeline.date.timeIntervalSinceReferenceDate, calm: reduceMotion)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(shouting ? "Coach Mane, shouting" : "Coach Mane")
    }

    /// One frame of the coach at time `t` (the share card renders a fixed
    /// frame: `TimelineView` doesn't draw in `ImageRenderer`).
    func figure(t: Double, calm: Bool = false) -> some View {
        let s = size / 120
        let yelling = shouting && !calm
        // Shout: the jaw never stops flapping; bursts make it bigger and
        // add a head shake. Between bursts it used to close and sit still.
        let burst = yelling ? max(0, sin(t * 2.2)) : 0
        let jaw = yelling ? (0.35 + 0.65 * abs(sin(t * 11))) * (0.6 + 0.4 * burst) : 0.08 + 0.04 * sin(t * 2)
        let shake = yelling ? sin(t * 18) * 4 * burst : 0
        let sway = calm ? 0 : sin(t * (shouting ? 5 : 2.2)) * (shouting ? 9 : 6)
        let breathe = 1 + (calm ? 0.01 : 0.02) * sin(t * 2)
        // Head: bobs while yelling; after "Did it", a slow proud nod
        let bob = yelling ? abs(sin(t * 5.5)) * -4 : 0
        let nod = (!shouting && !calm) ? sin(t * 2.4) * 5 : 0
        // A quick blink every ~3 s
        let blink = t.truncatingRemainder(dividingBy: 3.1) < 0.12

        return ZStack {
            // Shoulders / tank top.
            RoundedRectangle(cornerRadius: 24 * s, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .frame(width: 104 * s, height: 40 * s)
                .offset(y: 46 * s)

            // Neck.
            Rectangle().fill(Self.skinShade)
                .frame(width: 22 * s, height: 16 * s)
                .offset(y: 30 * s)

            // Long hair: a mane behind the head falling past the shoulders,
            // with strands on each side that swing.
            Ellipse().fill(Self.hair)
                .frame(width: 80 * s, height: 96 * s)
                .rotationEffect(.degrees(sway * 0.4), anchor: .top)
                .offset(y: 4 * s)
            ForEach(0..<3, id: \.self) { i in
                let spread = CGFloat(i) * 7
                Capsule().fill(Self.hair)
                    .frame(width: 13 * s, height: (62 - spread) * s)
                    .rotationEffect(.degrees(sway * (1 + Double(i) * 0.35) + 8 + Double(i) * 6), anchor: .top)
                    .offset(x: (-30 - spread) * s, y: (14 + spread * 0.6) * s)
                Capsule().fill(Self.hair)
                    .frame(width: 13 * s, height: (62 - spread) * s)
                    .rotationEffect(.degrees(sway * (1 + Double(i) * 0.35) - 8 - Double(i) * 6), anchor: .top)
                    .offset(x: (30 + spread) * s, y: (14 + spread * 0.6) * s)
            }

            head(jaw: jaw, s: s, blink: blink)
                .rotationEffect(.degrees(shake + nod))
                .offset(y: (-6 + bob) * s)
        }
        .scaleEffect(breathe)
        .frame(width: size, height: size)
    }

    private func head(jaw: Double, s: CGFloat, blink: Bool = false) -> some View {
        ZStack {
            // Face.
            Ellipse().fill(Self.skin)
                .frame(width: 58 * s, height: 68 * s)

            // Hair on top, parted, framing the face.
            Ellipse().fill(Self.hair)
                .frame(width: 64 * s, height: 30 * s)
                .offset(y: -29 * s)

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
            Capsule().fill(Color.black).frame(width: 6 * s, height: (blink ? 1.2 : 6) * s).offset(x: -11 * s, y: -1 * s)
            Capsule().fill(Color.black).frame(width: 6 * s, height: (blink ? 1.2 : 6) * s).offset(x: 11 * s, y: -1 * s)

            // Beard around the mouth; the jaw drops it.
            Ellipse().fill(Self.beard)
                .frame(width: 48 * s, height: (26 + 8 * jaw) * s)
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
    static let beard = Color(red: 0.48, green: 0.31, blue: 0.17)
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

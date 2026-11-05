import SwiftUI
import FavWidgetsCore

/// The cartoon above a Daily Dog's line: dogs running across, a game of
/// fetch, a dog chasing its tail, paw prints, raining treats, bouncing pups
/// or the wagging head. A different one each open (`DailyDogScene.next`).
/// Emoji dogs face left, so a dog running right is mirrored.
struct DailyDogSceneView: View {
    let scene: DailyDogScene
    var height: CGFloat = 230
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// Picks the scene for this open and remembers it, so the next one differs
    static func pickScene() -> DailyDogScene {
        let key = "favwidgets.dailyDog.lastScene"
        let scene = DailyDogScene.next(after: UserDefaults.standard.string(forKey: key), roll: Int.random(in: 0..<10_000))
        UserDefaults.standard.set(scene.rawValue, forKey: key)
        return scene
    }

    var body: some View {
        Group {
            if reduceMotion {
                Text("🐶").font(.system(size: 110))
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    GeometryReader { geo in
                        content(t: t, size: geo.size)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(t: Double, size: CGSize) -> some View {
        switch scene {
        case .wag: wag(t, size)
        case .zoomies: zoomies(t, size)
        case .fetch: fetch(t, size)
        case .tailChase: tailChase(t, size)
        case .pawPrints: pawPrints(t, size)
        case .treatRain: treatRain(t, size)
        case .bouncing: bouncing(t, size)
        }
    }

    private func emoji(_ text: String, _ size: CGFloat, facingRight: Bool = false) -> some View {
        Text(text).font(.system(size: size)).scaleEffect(x: facingRight ? -1 : 1, y: 1)
    }

    /// 0…1 sawtooth
    private func cycle(_ value: Double) -> Double { value - floor(value) }

    /// 0…1…0 triangle
    private func triangle(_ value: Double) -> Double { abs(cycle(value / 2) * 2 - 1) }

    /// A running dog's hop
    private func hop(_ t: Double, speed: Double = 9, height: Double = 10) -> Double { -abs(sin(t * speed)) * height }

    // MARK: Scenes

    /// The original head, now with a wiggle and a tongue-out tilt
    private func wag(_ t: Double, _ size: CGSize) -> some View {
        emoji("🐶", 110)
            .scaleEffect(1 + 0.07 * sin(t * 4.5))
            .rotationEffect(.degrees(9 * sin(t * 7)))
            .offset(y: -6 * abs(sin(t * 2.2)))
            .position(x: size.width / 2, y: size.height / 2)
    }

    /// Four dogs with the zoomies, crossing both ways at their own speeds
    private func zoomies(_ t: Double, _ size: CGSize) -> some View {
        let runners: [(dog: String, speed: Double, row: Double, size: CGFloat, right: Bool, phase: Double)] = [
            ("🐕", 0.42, 0.30, 58, true, 0.0),
            ("🐩", 0.30, 0.78, 48, false, 0.45),
            ("🦮", 0.36, 0.55, 52, true, 0.7),
            ("🐕‍🦺", 0.52, 0.12, 40, false, 0.2)
        ]
        let span = size.width + 140
        return ZStack {
            ForEach(Array(runners.enumerated()), id: \.offset) { index, runner in
                let p = cycle(t * runner.speed + runner.phase)
                let x = runner.right ? -70 + p * span : size.width + 70 - p * span
                let y = size.height * runner.row + hop(t + Double(index), speed: 10 + Double(index))
                HStack(spacing: 0) {
                    if runner.right { emoji("💨", runner.size * 0.45).opacity(0.7).scaleEffect(x: -1, y: 1) }
                    emoji(runner.dog, runner.size, facingRight: runner.right)
                    if !runner.right { emoji("💨", runner.size * 0.45).opacity(0.7) }
                }
                .rotationEffect(.degrees((runner.right ? 1 : -1) * 6 * sin(t * 10 + Double(index))))
                .position(x: x, y: y)
            }
        }
    }

    /// A tennis ball arcs across and a dog tears after it, then back again
    private func fetch(_ t: Double, _ size: CGSize) -> some View {
        let length = 2.6
        let round = Int(t / length)
        let u = cycle(t / length)
        let goingRight = round.isMultiple(of: 2)
        func across(_ f: Double) -> Double {
            let x = size.width * (0.08 + 0.84 * f)
            return goingRight ? x : size.width - x
        }
        let ballX = across(min(u * 1.15, 1))
        let ballY = size.height * 0.82 - sin(min(u * 1.15, 1) * .pi) * size.height * 0.7
        let dogF = max(0, (u - 0.12) / 0.88)
        let dogX = across(dogF * 0.95 - 0.04)
        let caught = u > 0.9
        return ZStack {
            if !caught {
                emoji("🎾", 32).rotationEffect(.degrees(t * 400)).position(x: ballX, y: ballY)
            }
            emoji("🐕", 64, facingRight: goingRight)
                .position(x: dogX, y: size.height * 0.8 + hop(t, speed: 11, height: 14))
            if caught {
                emoji("🎾", 22).position(x: dogX + (goingRight ? 26 : -26), y: size.height * 0.74)
                emoji("✨", 26).opacity(1 - (u - 0.9) * 10).position(x: dogX, y: size.height * 0.5)
            }
        }
    }

    /// Round and round after its own tail, a little dizzy now and then
    private func tailChase(_ t: Double, _ size: CGSize) -> some View {
        let angle = t * 4.2
        let center = CGPoint(x: size.width / 2, y: size.height * 0.58)
        let radius = min(size.width * 0.28, 90.0)
        let x = center.x + cos(angle) * radius
        let y = center.y + sin(angle) * radius * 0.45
        let movingRight = -sin(angle) > 0
        let dizzy = cycle(t / 5) > 0.75
        return ZStack {
            Ellipse()
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 10]))
                .frame(width: radius * 2, height: radius * 0.9)
                .rotationEffect(.degrees(t * -40))
                .position(center)
            emoji("🐕", 62, facingRight: movingRight)
                .scaleEffect(0.85 + 0.15 * (sin(angle) + 1) / 2)
                .position(x: x, y: y)
            if dizzy {
                emoji("💫", 34).rotationEffect(.degrees(t * 200)).position(x: x, y: y - 46)
            }
        }
    }

    /// A dog trots across leaving paw prints that fade behind it
    private func pawPrints(_ t: Double, _ size: CGSize) -> some View {
        let length = 5.0
        // Start with the dog already on screen
        let progress = t / length + 0.15
        let u = cycle(progress)
        let goingRight = Int(progress).isMultiple(of: 2)
        let steps = 11
        let travel = size.width + 120
        let dogDistance = u * travel - 60
        let dogX = goingRight ? dogDistance : size.width - dogDistance
        return ZStack {
            ForEach(0..<steps, id: \.self) { i in
                let distance = (Double(i) + 0.5) / Double(steps) * size.width
                let left = distance < dogDistance - 30
                let age = (dogDistance - distance) / travel
                emoji("🐾", 24)
                    .rotationEffect(.degrees(goingRight ? 90 : -90))
                    .opacity(left ? max(0, 0.95 - age * 1.6) : 0)
                    .position(x: goingRight ? distance : size.width - distance,
                              y: size.height * 0.72 + (i.isMultiple(of: 2) ? -9 : 9))
            }
            emoji("🐕", 60, facingRight: goingRight)
                .rotationEffect(.degrees(4 * sin(t * 8)))
                .position(x: dogX, y: size.height * 0.42 + hop(t, speed: 8, height: 6))
        }
    }

    /// Treats fall from the sky and a pup slides around trying to catch them
    private func treatRain(_ t: Double, _ size: CGSize) -> some View {
        let treats = ["🦴", "🍖", "🥓", "🧀", "🦴", "🌭", "🦴", "🍗"]
        let catcherX = size.width / 2 + sin(t * 1.4) * size.width * 0.33
        return ZStack {
            ForEach(treats.indices, id: \.self) { i in
                let lane = (Double((i * 37) % 100) / 100) * 0.84 + 0.08
                let speed = 0.32 + Double((i * 13) % 7) * 0.04
                let fall = cycle(t * speed + Double(i) * 0.61 + 0.13)
                emoji(treats[i], 28)
                    .rotationEffect(.degrees(t * (i.isMultiple(of: 2) ? 120 : -90)))
                    .opacity(fall > 0.85 ? (1 - fall) / 0.15 : 1)
                    .position(x: size.width * lane, y: -20 + fall * (size.height * 0.85))
            }
            emoji("🐶", 72)
                .rotationEffect(.degrees(cos(t * 1.4) * 10))
                .position(x: catcherX, y: size.height - 36 + hop(t, speed: 6, height: 5))
        }
    }

    /// Pup heads bouncing off the edges like an old screensaver
    private func bouncing(_ t: Double, _ size: CGSize) -> some View {
        let pups: [(face: String, vx: Double, vy: Double, px: Double, py: Double)] = [
            ("🐶", 0.23, 0.37, 0.1, 0.6),
            ("🐶", 0.31, 0.27, 0.7, 0.2),
            ("🐩", 0.19, 0.43, 0.4, 0.9)
        ]
        return ZStack {
            ForEach(Array(pups.enumerated()), id: \.offset) { index, pup in
                emoji(pup.face, 56)
                    .rotationEffect(.degrees(t * (index.isMultiple(of: 2) ? 70 : -55)))
                    .position(x: 32 + triangle(t * pup.vx + pup.px) * (size.width - 64),
                              y: 32 + triangle(t * pup.vy + pup.py) * (size.height - 64))
            }
        }
    }
}

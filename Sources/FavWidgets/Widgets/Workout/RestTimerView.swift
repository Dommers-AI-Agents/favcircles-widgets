import SwiftUI
import Combine
import FavWidgetsCore

/// Countdown banner pinned under the active session. Remaining time is
/// computed from `endsAt` on every tick so backgrounding never drifts it.
struct RestTimerView: View {
    @Binding var endsAt: Date?
    let theme: WidgetTheme
    let accent: Color
    /// Called once when the countdown reaches zero (not on skip).
    let onFinished: () -> Void

    @State private var remaining = 0
    @State private var ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        if let endsAt {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest").font(.system(size: 11, weight: .semibold)).opacity(0.8)
                    Text(WorkoutFormat.duration(TimeInterval(remaining)))
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                }
                Spacer()
                bannerButton("+30s") { self.endsAt = endsAt.addingTimeInterval(30); tick() }
                bannerButton("Skip") { self.endsAt = nil }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onAppear(perform: tick)
            .onReceive(ticker) { _ in tick() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func bannerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }

    private func tick() {
        guard let endsAt else { return }
        let left = Int(endsAt.timeIntervalSinceNow.rounded(.up))
        if left <= 0 {
            remaining = 0
            self.endsAt = nil
            onFinished()
        } else {
            remaining = left
        }
    }
}

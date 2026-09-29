import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Keeps the screen from dimming and locking while a widget is doing
/// something the person is watching (a heart-rate measurement, a live strap
/// reading). Counted, so two screens asking at once don't switch each other
/// off, and always released when the view goes away.
@MainActor
enum ScreenAwake {
    private static var holders = 0

    static func acquire() {
        holders += 1
        apply()
    }

    static func release() {
        holders = max(0, holders - 1)
        apply()
    }

    private static func apply() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = holders > 0
        #endif
    }
}

private struct KeepsScreenAwake: ViewModifier {
    let active: Bool
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onAppear { sync(active) }
            .onChange(of: active) { sync($0) }
            .onDisappear { sync(false) }
    }

    private func sync(_ want: Bool) {
        guard want != holding else { return }
        holding = want
        if want { ScreenAwake.acquire() } else { ScreenAwake.release() }
    }
}

extension View {
    /// The screen stays on while `active` is true and this view is showing.
    func keepsScreenAwake(_ active: Bool) -> some View {
        modifier(KeepsScreenAwake(active: active))
    }
}

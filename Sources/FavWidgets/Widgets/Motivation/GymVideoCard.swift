import SwiftUI
#if os(iOS)
import WebKit
#endif
import FavWidgetsCore

/// The "go to the gym" reminder on the Motivation widget's main screen
/// (Wes, 2026-10-21): a tile that plays the video right here.
struct GymVideoCard: View {
    let context: WidgetContext
    let theme: WidgetTheme
    @State private var playing = false

    var body: some View {
        Button {
            context.track("motivation_gym_video", ["from": "tile"])
            context.host.haptic(.light)
            playing = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [.black, context.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "play.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 64, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(MotivationShareText.gymVideoCaption).font(.system(size: 16, weight: .bold)).foregroundStyle(theme.label)
                    Text("Watch this whenever you need the push.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch the go to the gym video")
        .sheet(isPresented: $playing) { player }
    }

    private var player: some View {
        VStack(spacing: 12) {
            #if os(iOS)
            GymVideoWebView(url: URL(string: MotivationShareText.gymVideoPlayerURL))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            #endif
            Button {
                if let url = URL(string: MotivationShareText.gymVideoURL) { context.host.openURL(url) }
            } label: {
                Label("Open in TikTok", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(context.accent)
        }
        .padding(16)
        .background(theme.background.ignoresSafeArea())
    }
}

#if os(iOS)
private struct GymVideoWebView: UIViewRepresentable {
    let url: URL?
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        if let url { view.load(URLRequest(url: url)) }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

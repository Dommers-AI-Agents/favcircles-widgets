import SwiftUI
#if os(iOS)
import WebKit
#endif
import FavWidgetsCore

/// The "go to the gym" reminder on the Motivation widget's main screen
/// (Wes, 2026-10-21): a tile that plays the video right here. The player's
/// Share sends our own link (`/app/widget/motivation?video=gym`), which opens
/// this player straight away (Wes, 2026-11-27).
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
        .task { await openLaunchedVideo() }
    }

    /// A shared video link: the page opens with the player already up.
    private func openLaunchedVideo() async {
        guard context.launchMotivationVideoId != nil else { return }
        context.launchMotivationVideoId = nil   // contexts are reused
        context.track("motivation_gym_video", ["from": "link"])
        await context.presentLaunched { playing = true }
    }

    /// One tappable bubble: the video's card and our link, which opens the
    /// video in FavCircles (or the App Store for someone without it).
    private func share() {
        guard let url = MotivationShareText.gymVideoShareURL else { return }
        context.track("motivation_gym_video_shared")
        context.host.haptic(.light)
        context.host.share([.link(url, title: MotivationShareText.gymVideoShareTitle,
                                  imageJPEG: GymVideoShareCard.jpeg(accent: context.accent))])
    }

    private var player: some View {
        VStack(spacing: 12) {
            #if os(iOS)
            GymVideoWebView(url: URL(string: MotivationShareText.gymVideoPlayerURL))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            #endif
            HStack(spacing: 10) {
                Button { share() } label: {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(context.accent)
                Button {
                    if let url = URL(string: MotivationShareText.gymVideoURL) { context.host.openURL(url) }
                } label: {
                    Label("Open in TikTok", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(context.accent)
            }
        }
        .padding(16)
        .background(theme.background.ignoresSafeArea())
    }
}

/// The picture a shared video link shows in Messages: a play button and the
/// caption, in Coach Mane's colors. Ours, not a frame of the TikTok.
private struct GymVideoShareCard: View {
    let accent: Color

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 120, height: 120)
                Image(systemName: "play.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 4)
            }
            Text("Go to the gym")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Coach Mane · FavCircles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(32)
        .frame(width: 400, height: 400)
        .background(LinearGradient(colors: [.black, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    @MainActor
    static func jpeg(accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: GymVideoShareCard(accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
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

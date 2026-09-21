import SwiftUI
import FavWidgetsCore

/// The quote reel: one line per screen, swiped vertically, opening on
/// whichever quote you tapped in the notification and continuing into the
/// ones most like it.
///
/// Vertical paging on iOS 16 has no first-class API — `scrollTargetBehavior`
/// is 17+. The standard answer, used here, is a horizontal paging `TabView`
/// turned on its side: the container is rotated -90°, each page rotated back.
/// It is a trick, but it is the trick, and it behaves correctly with
/// VoiceOver and the page indicator hidden.
struct QuotesReelView: View {
    let context: WidgetContext
    /// The quote to open on — from the tapped push, or the card.
    let startId: String?
    let onClose: () -> Void

    @State private var quotes: [QuoteReelItem] = []
    @State private var selection: Int = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var categories: [String: String] = [:]

    var body: some View {
        ZStack {
            context.theme.background.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(context.accent)
            } else if let loadError {
                failure(loadError)
            } else if quotes.isEmpty {
                Text("No quotes yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(context.theme.secondaryLabel)
            } else {
                reel
            }
            closeButton
        }
        .task { await load() }
    }

    // MARK: - The reel

    #if os(iOS)
    private var reel: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                    page(quote)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .rotationEffect(.degrees(90))
                        .tag(index)
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .rotationEffect(.degrees(-90))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: selection) { index in
            guard let quote = quotes[safe: index] else { return }
            context.track("quote_reel_viewed", ["quote_id": quote.id])
        }
    }
    #else
    // Nothing reads quotes on a Mac; this only has to compile so the package
    // keeps building for the platform FavWidgetsCore is tested on.
    private var reel: some View {
        ScrollView { VStack(spacing: 24) { ForEach(quotes) { page($0) } } }
    }
    #endif

    private func page(_ quote: QuoteReelItem) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(quote.text)
                // Long quotes shrink rather than truncate — a clipped quote is
                // worse than a small one.
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(theme.label)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
            if let attribution = quote.attribution {
                Text(attribution)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(context.accent)
                    .padding(.top, 16)
            }
            if let note = quote.context, !note.isEmpty {
                Text(note)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            if !quote.categories.isEmpty {
                HStack(spacing: 6) {
                    ForEach(quote.categories, id: \.self) { id in
                        Text(categories[id] ?? id.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(context.accent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(context.accent.opacity(0.15)))
                    }
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                Button { share(quote) } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
                Spacer()
                if quotes.count > 1 {
                    Text("Swipe for more")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(context.theme.secondaryLabel)
                        .padding(10)
                        .background(Circle().fill(context.theme.secondaryBackground))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(context.theme.secondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(context.accent)
        }
        .padding(28)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let response = try await QuotesAPI.feed(context: context, start: startId)
            quotes = response.quotes
            categories = Dictionary(uniqueKeysWithValues: response.categories.map { ($0.id, $0.label) })
            // The server puts the tapped quote first when it still exists, so
            // opening at 0 is right; finding it by id keeps that true if the
            // ordering contract ever changes.
            selection = startId.flatMap { id in quotes.firstIndex(where: { $0.id == id }) } ?? 0
            if let first = quotes[safe: selection] {
                context.track("quote_reel_opened", ["quote_id": first.id])
            }
        } catch {
            loadError = "Couldn't load quotes. Check your connection."
        }
        isLoading = false
    }

    private func share(_ quote: QuoteReelItem) {
        let line = quote.attribution.map { "\(quote.text)\n\($0)" } ?? quote.text
        context.track("quote_shared", ["quote_id": quote.id])
        context.host.share([.text(line)])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension View {
    /// Full screen on iOS, a sheet on macOS — `fullScreenCover` doesn't exist
    /// there. The reel wants the whole screen: one quote, nothing else.
    @ViewBuilder
    internal func quoteReelCover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

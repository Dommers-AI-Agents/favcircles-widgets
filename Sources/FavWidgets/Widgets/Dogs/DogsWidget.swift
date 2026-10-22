import SwiftUI
import FavWidgetsCore

/// Can I Pet Dat Dog (Wes, 2026-10-22: "a more playful app for dog lovers.
/// Less of an app for practical uses but perhaps adding some of that. Like,
/// add your doggie picture, health records, insurance, and favorite dog
/// places. But also like send me daily funny dog things. Let other users join
/// the community of dogs to see more pictures funny things").
///
/// Three tabs: the Dog Park (everyone's dog photos and 15-second clips, Pet
/// instead of like, comments), Daily Dog (a funny line or the community's
/// most-petted pup, pushed at the times you pick) and My Dogs (profiles plus
/// private health records, insurance, the vet, favorite dog spots and
/// "Import from your vet"). Health and insurance never leave the private
/// document; certificate and card photos never leave the phone.
public struct DogsWidget: FavWidget {
    public init() {}

    public static let widgetId = "dogs"

    public let descriptor = FavWidgetDescriptor(
        id: DogsWidget.widgetId,
        title: "Can I Pet Dat Dog",
        subtitle: "Dog pics, daily laughs and your pup's records",
        symbolName: "pawprint.fill",
        accentHex: "#E8954A",
        category: .social,
        storage: .single,
        schemaVersion: DogsState.schemaVersion,
        shareBlurb: "A happy place for dog people: post your pup, pet everyone else's, get a funny dog thing every day, and keep your dog's vet records and insurance in one spot."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(DogsCardView(context: context, store: DogsStore.shared(in: context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(DogsFullView(context: context, store: DogsStore.shared(in: context), state: context.state(DogsState.self)))
    }

    public func refresh(context: WidgetContext) async {
        await DogsStore.shared(in: context).refresh(context, force: true)
        await context.state(DogsState.self).reload()
    }

    /// My latest Dog Park post, else today's Daily Dog, else my dog; each
    /// linking straight to it. Never health or insurance.
    @MainActor
    public func shareCard(context: WidgetContext) async -> WidgetShareCardContent? {
        let store = DogsStore.shared(in: context)
        await store.refresh(context)
        guard store.me.member else { return nil }
        let mine = DogFeedTab.allCases.compactMap { store.feeds[$0] }.flatMap { $0 }.filter(\.mine)
            .max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let post = mine { return DogsWidget.shareCardContent(post, image: await DogShareImages.jpeg(post.thumbnailURL)) }
        if let today = store.me.today {
            return DogsWidget.shareCardContent(today, image: await DogShareImages.jpeg(today.post?.thumbnailURL))
        }
        if let dog = store.me.dogs.first { return DogsWidget.shareCardContent(dog, image: await DogShareImages.jpeg(dog.photoURL)) }
        return nil
    }

    static func shareCardContent(_ post: DogPost, image: Data?) -> WidgetShareCardContent {
        WidgetShareCardContent(
            headline: "🐶 \(post.dogNames ?? "Can I pet dat dog?")",
            detail: post.caption.isEmpty ? nil : post.caption,
            stats: post.petCount > 0 ? [.init("\(post.petCount)", post.petCount == 1 ? "pet" : "pets")] : [],
            imageJPEG: image,
            linkTitle: "🐾 Can I pet \(post.dogNames ?? "dat dog")?",
            url: post.linkURL
        )
    }

    static func shareCardContent(_ daily: DailyDog, image: Data?) -> WidgetShareCardContent {
        WidgetShareCardContent(
            headline: "\(daily.kind.emoji) \(daily.kind.label)",
            detail: daily.text.isEmpty ? daily.post?.dogNames : daily.text,
            imageJPEG: image,
            linkTitle: "🐾 Today's Daily Dog",
            url: daily.linkURL
        )
    }

    static func shareCardContent(_ dog: DogProfile, image: Data?) -> WidgetShareCardContent {
        let sub = DogCopy.subtitle(dog)
        return WidgetShareCardContent(
            headline: "🐶 Meet \(dog.name)",
            detail: [sub.isEmpty ? nil : sub, dog.personality.isEmpty ? nil : dog.personality].compactMap { $0 }.joined(separator: "\n"),
            imageJPEG: image,
            linkTitle: "🐾 Can I pet \(dog.name)?",
            url: nil
        )
    }
}

/// The picture a share card carries (small, already cached when seen).
enum DogShareImages {
    static func jpeg(_ url: URL?) async -> Data? {
        guard let url, let image = await RemoteImageCache.image(for: url) else { return nil }
        #if os(iOS)
        return image.jpegData(compressionQuality: 0.8)
        #else
        return nil
        #endif
    }
}

/// Card: today's Daily Dog, or the pitch.
struct DogsCardView: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction(store.me.member ? "Dog Park" : "Join", symbolName: "pawprint.fill") {
            context.openFullView()
        }) {
            if store.me.member, let today = store.me.today {
                HStack(spacing: 10) {
                    if let url = today.post?.thumbnailURL {
                        WidgetUI.thumbnail(url: url, width: 44, height: 44, cornerRadius: 10, background: theme.tertiaryBackground,
                                           fallbackSymbol: "pawprint.fill", fallbackColor: context.accent, contentMode: .fill)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(today.kind.emoji) \(today.kind.label)").font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                        Text(today.text.isEmpty ? (today.post?.dogNames ?? "Can I pet dat dog?") : today.text)
                            .font(.system(size: 14)).foregroundStyle(theme.label).lineLimit(2)
                    }
                }
            } else if store.me.member, let dog = store.me.dogs.first {
                WidgetUI.summary("🐶 \(dog.name) is ready for the Dog Park. Post a pic and collect pets!", theme: theme)
            } else {
                WidgetUI.summary("Can I pet dat dog? 🐾 Dog pics, daily laughs and your pup's records", theme: theme)
            }
        }
        .task { await store.refresh(context) }
    }
}

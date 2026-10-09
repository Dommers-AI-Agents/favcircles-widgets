import SwiftUI
import FavWidgetsCore

/// The one share-card design every widget uses (Workouts' look): the
/// widget's colour, its icon and name, a headline, an optional picture and
/// numbers, and FavCircles at the foot. Rendered to a JPEG for the share
/// sheet; the recipient taps it to land on the widget.
struct WidgetShareCardView: View {
    let descriptor: FavWidgetDescriptor
    let content: WidgetShareCardContent

    private var accent: Color { Color(hex: descriptor.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: descriptor.symbolName).font(.system(size: 15, weight: .semibold))
                Text(descriptor.title).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 3) {
                Text(content.headline).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
                if let detail = content.detail {
                    Text(detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                }
            }
            #if os(iOS)
            if let data = content.imageJPEG, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 356, height: 200).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            #endif
            if !content.stats.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(content.stats.enumerated()), id: \.offset) { _, stat in
                        VStack(spacing: 0) {
                            Text(stat.value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(stat.label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Text("FavCircles").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(22)
        .frame(width: 400, alignment: .leading)
        .background(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Share any widget: its own card when it has one, otherwise the generic
/// card. The shell's Share button (every widget page) calls this, so a new
/// widget has a share card from day one.
@MainActor
public enum WidgetShareKit {
    public static func items(for widget: any FavWidget, context: WidgetContext) async -> [WidgetShareItem] {
        let content = await widget.shareCard(context: context) ?? .generic(widget.descriptor)
        return items(descriptor: widget.descriptor, content: content)
    }

    public static func items(descriptor: FavWidgetDescriptor, content: WidgetShareCardContent) -> [WidgetShareItem] {
        WidgetShareCard.items(widgetId: descriptor.id, content: content, cardJPEG: jpeg(descriptor: descriptor, content: content))
    }

    static func jpeg(descriptor: FavWidgetDescriptor, content: WidgetShareCardContent) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: WidgetShareCardView(descriptor: descriptor, content: content))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.88)
        #else
        return nil
        #endif
    }
}

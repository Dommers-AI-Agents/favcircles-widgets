import SwiftUI

/// The postcard itself, drawn identically for the on-screen preview, the
/// template thumbnails, and the JPEG that gets sent. Renders synchronously
/// (no async images, no GeometryReader) so `ImageRenderer` sees the final
/// pixels; every metric scales with `size` so a thumbnail is a true miniature.
struct PostcardCanvasView: View {
    let image: PostcardPlatformImage?
    let templateId: String
    let caption: String
    let size: CGSize
    var accent: Color = Color(red: 0.90, green: 0.24, blue: 0.24)
    /// Extra inset, in render points, held between the artwork edge and every
    /// piece of content. Zero on screen. For print it's the bleed the trimmer
    /// cuts away, so backgrounds and photos still run off the edge while
    /// captions and the stamp stay safely inside the finished card.
    var bleed: CGFloat = 0

    private var template: PostcardTemplate { PostcardTemplate.resolve(templateId) }
    /// 1.0 at the 600pt design width.
    private var scale: CGFloat { max(0.2, size.width / 600) }

    var body: some View {
        Group {
            switch template {
            case .classic: classic
            case .vintage: vintage
            case .modern: modern
            case .polaroid: polaroid
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Templates

    private var classic: some View {
        let border = 18 * scale + bleed
        return ZStack(alignment: .topTrailing) {
            Color.white
            photo
                .padding(border)
                .overlay(alignment: .bottomLeading) {
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3 * scale, x: 0, y: 1 * scale)
                            .padding(border + 14 * scale)
                    }
                }
            stamp
                .padding(border + 10 * scale)
        }
    }

    private var vintage: some View {
        let border = 22 * scale + bleed
        let cream = Color(red: 0.96, green: 0.93, blue: 0.84)
        return ZStack {
            cream
            photo
                .overlay(Color(red: 0.55, green: 0.38, blue: 0.16).opacity(0.28))
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                )
                .saturation(0.6)
                .contrast(0.95)
                .padding(border)
                .overlay(alignment: .bottom) {
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 30 * scale, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(cream)
                            .shadow(color: .black.opacity(0.5), radius: 2 * scale, x: 0, y: 1 * scale)
                            .padding(.bottom, border + 14 * scale)
                    }
                }
            RoundedRectangle(cornerRadius: 2 * scale)
                .stroke(Color(red: 0.62, green: 0.50, blue: 0.32).opacity(0.5), lineWidth: 1.5 * scale)
                .padding(border - 6 * scale)
        }
    }

    private var modern: some View {
        let bandHeight = 74 * scale + bleed
        return ZStack(alignment: .bottom) {
            photo
            Rectangle()
                .fill(accent)
                .frame(height: bandHeight)
                .overlay(alignment: .leading) {
                    HStack(spacing: 10 * scale) {
                        Rectangle().fill(.white).frame(width: 5 * scale, height: bandHeight * 0.5)
                        Text(caption.isEmpty ? "Greetings" : caption)
                            .font(.system(size: 28 * scale, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.horizontal, 22 * scale + bleed)
                    .padding(.bottom, bleed)
                }
        }
    }

    private var polaroid: some View {
        let side = 20 * scale + bleed
        let bottom = 84 * scale + bleed
        return ZStack(alignment: .bottom) {
            Color.white
            VStack(spacing: 0) {
                photo
                    .padding(.top, side)
                    .padding(.horizontal, side)
                Spacer(minLength: 0)
                    .frame(height: bottom)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.custom("Bradley Hand", size: 30 * scale))
                    .italic()
                    .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.20))
                    .frame(height: bottom)
                    .padding(.bottom, bleed)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 4 * scale, x: 0, y: 2 * scale)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var photo: some View {
        if let image {
            Color.clear
                .overlay(
                    Image(postcardImage: image)
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
        } else {
            ZStack {
                LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo")
                    .font(.system(size: 44 * scale, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var stamp: some View {
        let side = 52 * scale
        let initial = caption
            .replacingOccurrences(of: "Greetings from ", with: "")
            .trimmingCharacters(in: .whitespaces)
            .first.map { String($0).uppercased() } ?? "✈︎"
        return ZStack {
            Rectangle().fill(Color.white)
            Rectangle()
                .stroke(accent, lineWidth: 2 * scale)
                .padding(4 * scale)
            Text(initial)
                .font(.system(size: 24 * scale, weight: .bold, design: .serif))
                .foregroundStyle(accent)
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(4))
        .shadow(color: .black.opacity(0.2), radius: 2 * scale, x: 0, y: 1 * scale)
    }
}

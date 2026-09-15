import SwiftUI
import FavWidgetsCore

/// A price line, colored by where it sits against the reference (previous
/// close) the way Yahoo's charts are. With `filled`, the area under the
/// line is tinted and the reference is drawn dashed; without, it's the
/// small inline sparkline used in list rows.
struct StockSparklineView: View {
    let points: [StockPricePoint]
    let reference: Double?
    var filled = false
    var lineWidth: CGFloat = 1.5
    let upColor: Color
    let downColor: Color

    private var closes: [Double] { points.map(\.close) }

    private var isUp: Bool {
        guard let last = closes.last else { return true }
        return last >= (reference ?? closes.first ?? last)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let color = isUp ? upColor : downColor
            if closes.count >= 2 {
                let bounds = Self.bounds(closes: closes, reference: filled ? reference : nil)
                let path = Self.linePath(closes: closes, in: size, bounds: bounds)
                if filled {
                    Self.areaPath(closes: closes, in: size, bounds: bounds)
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    if let reference {
                        let y = Self.y(reference, in: size, bounds: bounds)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                path.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            } else {
                // One bar or none: a flat hairline so the row doesn't jump
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Geometry (static so it stays trivially testable)

    static func bounds(closes: [Double], reference: Double?) -> ClosedRange<Double> {
        var low = closes.min() ?? 0
        var high = closes.max() ?? 1
        if let reference {
            low = min(low, reference)
            high = max(high, reference)
        }
        if high - low < 0.000001 {   // flat line: give it some room
            low -= 1
            high += 1
        }
        let pad = (high - low) * 0.06
        return (low - pad)...(high + pad)
    }

    static func y(_ value: Double, in size: CGSize, bounds: ClosedRange<Double>) -> CGFloat {
        let fraction = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return size.height - CGFloat(fraction) * size.height
    }

    static func linePath(closes: [Double], in size: CGSize, bounds: ClosedRange<Double>) -> Path {
        var path = Path()
        let step = size.width / CGFloat(max(1, closes.count - 1))
        for (index, close) in closes.enumerated() {
            let point = CGPoint(x: CGFloat(index) * step, y: y(close, in: size, bounds: bounds))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    static func areaPath(closes: [Double], in size: CGSize, bounds: ClosedRange<Double>) -> Path {
        var path = linePath(closes: closes, in: size, bounds: bounds)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Yahoo's change pill: white text on solid green/red.
struct StockChangePill: View {
    let text: String
    let isUp: Bool
    let upColor: Color
    let downColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isUp ? upColor : downColor))
    }
}

enum StockPalette {
    /// Yahoo's greens and reds.
    static let up = Color(red: 0.0, green: 0.53, blue: 0.29)     // #00873C
    static let down = Color(red: 1.0, green: 0.31, blue: 0.24)   // #FF4E3E
}

extension View {
    /// Tickers are typed in capitals; the modifier only exists on iOS.
    @ViewBuilder
    func stockSymbolKeyboard() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }
}

/// "At close: 4:00 PM EDT", "Live", "Pre-market" — Yahoo's status line.
enum StockStatusLine {
    static func text(state: StockMarketState?, asOf: Date?, timezone: String?) -> String? {
        guard let state else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a zzz"
        if let timezone, let zone = TimeZone(identifier: timezone) { formatter.timeZone = zone }
        let stamp = asOf.map { formatter.string(from: $0) }
        switch state {
        case .live: return "Live" + (stamp.map { " · \($0)" } ?? "")
        case .preMarket: return "Pre-market" + (stamp.map { " · At close: \($0)" } ?? "")
        case .afterHours, .closed: return stamp.map { "At close: \($0)" } ?? "Market closed"
        }
    }
}

import SwiftUI
import FavWidgetsCore

/// The parent's answer control for one open question, by kind: big choice
/// buttons, a 0–10 slider with the question's own end labels, or a line
/// of text. Large type and tall targets on purpose — the person answering
/// may be eighty.
struct CareAnswerControls: View {
    let context: WidgetContext
    let ask: CareAsk
    let disabled: Bool
    let send: (CareAnswerPayload) -> Void

    @State private var score: Double = 5
    @State private var touched = false
    @State private var words = ""

    var body: some View {
        switch ask.kind {
        case .scale: scale
        case .text: text
        case .mood, .done, .yesno, .unknown: choices
        }
    }

    // MARK: - Choices

    private var choices: some View {
        let theme = context.theme
        let options = ask.kind.choices
        return VStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let highlighted = index == 0
                Button { send(.choice(option.key)) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: option.key)).font(.system(size: 18, weight: .semibold))
                        Text(option.label).font(.system(size: 18, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(highlighted ? .white : theme.label)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(highlighted ? context.accent : theme.tertiaryBackground))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
    }

    private func symbol(for key: String) -> String {
        switch ask.kind {
        case .mood, .unknown: return CareAnswer(rawValue: key)?.symbolName ?? "hand.raised.fill"
        default:
            switch key {
            case "yes": return "checkmark.circle.fill"
            case "not_yet": return "clock"
            default: return "xmark.circle"
            }
        }
    }

    // MARK: - 0–10

    private var scale: some View {
        let theme = context.theme
        return VStack(spacing: 12) {
            Text(touched ? "\(Int(score))" : "—")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(touched ? context.accent : theme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(touched ? "\(Int(score)) out of 10" : "Not chosen yet")
            Slider(value: $score, in: 0...10, step: 1) { _ in touched = true }
                .tint(context.accent)
            HStack {
                Text("0 · \(ask.low ?? "")").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                Spacer()
                Text("\(ask.high ?? "") · 10").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
            WidgetUI.primaryButton(touched ? "Send \(Int(score))" : "Slide to answer", color: context.accent) {
                guard touched else { return }
                send(.scale(Int(score)))
            }
            .disabled(disabled || !touched)
            .opacity(touched ? 1 : 0.6)
        }
    }

    // MARK: - Words

    private var text: some View {
        let theme = context.theme
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 10) {
            TextField("A few words is plenty", text: $words, axis: .vertical)
                .font(.system(size: 17))
                .lineLimit(2...4)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.tertiaryBackground))
                .onSubmit { if !trimmed.isEmpty { send(.text(trimmed)) } }
            WidgetUI.primaryButton("Send", color: context.accent) {
                guard !trimmed.isEmpty else { return }
                send(.text(trimmed))
            }
            .disabled(disabled || trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.6 : 1)
        }
    }
}

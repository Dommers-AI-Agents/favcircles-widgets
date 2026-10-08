import SwiftUI
import FavWidgetsCore

/// One answer, opened from its push or from the answers list (Wes,
/// 2026-10-08: "Sal: Sleep 6/10" should open that answer, not the widget's
/// front page): the answer, reactions and comments (each pings the person
/// checked on; their reply pings the family), then how they've answered
/// the same question before.
struct CareAnswerDetailView: View {
    let context: WidgetContext
    @ObservedObject var store: CareStore
    let askId: String

    @Environment(\.dismiss) private var dismiss
    @State private var ask: CareAsk?
    @State private var history: [CareAsk] = []
    @State private var parentName: String?
    @State private var role: String?
    @State private var failed = false
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var typing: Bool

    private var theme: WidgetTheme { context.theme }
    private var isParent: Bool { role == "parent" }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let ask {
                    VStack(alignment: .leading, spacing: 20) {
                        answerBlock(ask)
                        if ask.isAnswered { commentsBlock(ask) }
                        historyBlock(ask)
                    }
                    .padding(16)
                } else if failed {
                    Text("This answer isn't available.")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(parentName.map { isParent ? "Your answer" : $0 } ?? "Answer")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .onReceive(store.$lastChangedAsk) { changed in
                if let changed, changed.askId == askId { ask = changed }
            }
        }
    }

    private func load() async {
        do {
            let detail = try await CareAPI.askDetail(context: context, askId: askId)
            ask = detail.ask; history = detail.history; parentName = detail.parentName; role = detail.role
            context.track("care_answer_opened", ["role": detail.role ?? "?"])
        } catch {
            failed = true
        }
    }

    // MARK: - The answer

    private func answerBlock(_ ask: CareAsk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ask.questionText).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
            HStack(alignment: .center, spacing: 12) {
                Text(CareAnswerRow.answerLine(ask))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(ask.alert ? theme.warning : theme.label)
                if ask.kind == .scale, let score = ask.answerScore { CareScaleBar(context: context, value: score, warn: ask.alert) }
            }
            if !ask.note.isEmpty { Text("“\(ask.note)”").font(.system(size: 16)).foregroundStyle(theme.label) }
            Text(CareCopy.relative(ask.answeredAt ?? ask.askedAt, calendar: context.calendar))
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            if ask.isAnswered {
                if isParent {
                    CareParentSupportLines(context: context, ask: ask).padding(.top, 4)
                } else {
                    CareFamilySupportBar(context: context, ask: ask, store: store).padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
    }

    // MARK: - Comments

    private func commentsBlock(_ ask: CareAsk) -> some View {
        let me = context.host.currentUserId
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Comments", theme: theme)
            ForEach(ask.comments) { c in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(c.userId == me ? "You" : c.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.label)
                        if let at = c.at {
                            Text(CareCopy.relative(at, calendar: context.calendar)).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    Text(c.text).font(.system(size: 15)).foregroundStyle(theme.label)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField(isParent ? "Reply to your family" : "Say something to \(firstName)", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($typing)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.tertiaryBackground))
                Button { send(ask) } label: {
                    if sending { ProgressView().frame(width: 34, height: 34) } else {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                            .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.secondaryLabel : context.accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send comment")
            }
            Text(isParent ? "Your family gets a notification." : "\(firstName) gets a notification.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private var firstName: String {
        (parentName ?? "them").split(separator: " ").first.map(String.init) ?? "them"
    }

    private func send(_ ask: CareAsk) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let updated = try await CareAPI.comment(context: context, askId: ask.askId, text: text)
                draft = ""
                typing = false
                store.replaceAsk(updated)
                context.host.haptic(.success)
                context.track("care_commented", ["role": role ?? "?"])
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't send", message: error.localizedDescription))
            }
        }
    }

    // MARK: - History

    private func historyBlock(_ ask: CareAsk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetUI.header(ask.short.map { "\($0) before" } ?? "This question before", theme: theme)
            if history.isEmpty {
                Text("This is the first time it was asked.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
            ForEach(history) { past in
                HStack(spacing: 10) {
                    Text(past.askedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        .frame(width: 92, alignment: .leading)
                    Text(CareAnswerRow.answerLine(past))
                        .font(.system(size: 15, weight: past.isAnswered ? .medium : .regular))
                        .foregroundStyle(past.isAnswered ? (past.alert ? theme.warning : theme.label) : theme.secondaryLabel)
                        .lineLimit(1)
                    Spacer()
                    if past.kind == .scale, let score = past.answerScore { CareScaleBar(context: context, value: score, warn: past.alert) }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

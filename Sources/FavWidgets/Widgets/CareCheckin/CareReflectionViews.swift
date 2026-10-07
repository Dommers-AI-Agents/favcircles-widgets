import SwiftUI
import FavWidgetsCore

// Pieces shared by both sides of How Are You?: the family's plan detail and
// the parent's own "Your week". The numbers come from CareReflection /
// CareCopy in FavWidgetsCore; these only draw them.

/// A 0–10 answer as ten small blocks.
struct CareScaleBar: View {
    let context: WidgetContext
    let value: Int
    var warn = false

    var body: some View {
        let theme = context.theme
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < value ? (warn ? theme.warning : context.accent) : theme.tertiaryBackground)
                    .frame(width: 6, height: 14)
            }
        }
        .accessibilityLabel("\(value) out of 10")
    }
}

/// One asked question and what came of it: glyph, question, answer, note, when.
struct CareAnswerRow: View {
    let context: WidgetContext
    let ask: CareAsk
    var support: CareSupportMode = .none

    var body: some View {
        let theme = context.theme
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: CareCopy.answerSymbol(ask))
                .font(.system(size: 14))
                .foregroundStyle(ask.alert ? theme.warning : (ask.isAnswered ? context.accent : theme.secondaryLabel)).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ask.questionText).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                HStack(spacing: 8) {
                    Text(Self.answerLine(ask)).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
                    if ask.kind == .scale, let score = ask.answerScore { CareScaleBar(context: context, value: score, warn: ask.alert) }
                }
                if !ask.note.isEmpty { Text("“\(ask.note)”").font(.system(size: 13)).foregroundStyle(theme.label) }
                Text(CareCopy.relative(ask.askedAt, calendar: context.calendar)).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                if ask.isAnswered {
                    switch support {
                    case .family(let store): CareFamilySupportBar(context: context, ask: ask, store: store).padding(.top, 4)
                    case .parent: CareParentSupportLines(context: context, ask: ask).padding(.top, 2)
                    case .none: EmptyView()
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    static func answerLine(_ ask: CareAsk) -> String {
        if let text = ask.answerText { return text }
        if ask.isMissed { return ask.pushDelivered ? "No answer" : "Not delivered" }
        return "Waiting…"
    }
}

/// The parent's own answers, looked back on: the week strip with a streak,
/// how the 0–10 answers are moving, the daily habits, and every recent
/// answer. Before this, the person being checked on saw only today's
/// question and one "last answer" line — the family saw the trends, they
/// didn't. Written for someone who may not use apps much: big words, no jargon.
struct CareMyWeekView: View {
    let context: WidgetContext
    let history: [CareAsk]
    @State private var showAll = false

    var body: some View {
        let theme = context.theme
        let now = Date()
        let days = CareReflection.days(history, now: now, calendar: context.calendar)
        let rate = CareCopy.answerRate(history, now: now)
        let streak = CareReflection.streak(history, now: now, calendar: context.calendar)
        let series = CareReflection.scaleSeries(history, now: now)
        let habits = CareReflection.habits(history, now: now)
        let answered = history.filter { $0.isAnswered || $0.isMissed }

        VStack(alignment: .leading, spacing: 16) {
            // The week
            VStack(alignment: .leading, spacing: 10) {
                WidgetUI.header("Your week", theme: theme)
                Text(CareReflection.weekHeadline(answered: rate.answered, asked: rate.asked, streak: streak))
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        dayCell(day).frame(maxWidth: .infinity)
                    }
                }
            }

            // How the 0–10 answers are moving
            if !series.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetUI.header("Over the last two weeks", theme: theme)
                    ForEach(series, id: \.short) { seriesCard($0) }
                }
            }

            // The daily habits
            if !habits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetUI.header("This week's habits", theme: theme)
                    ForEach(habits, id: \.question) { habit in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: habit.yes == habit.answered ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                                .font(.system(size: 16)).foregroundStyle(context.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.question).font(.system(size: 14)).foregroundStyle(theme.label)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(CareReflection.habitLine(habit)).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                            }
                        }
                    }
                }
            }

            // Every recent answer
            if !answered.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetUI.header("Your answers", theme: theme)
                    ForEach(showAll ? answered : Array(answered.prefix(6))) { CareAnswerRow(context: context, ask: $0, support: .parent) }
                    if answered.count > 6 {
                        Button(showAll ? "Show fewer" : "Show all \(answered.count)") { showAll.toggle() }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                }
            }
        }
    }

    /// A day in the strip: its letter, then its mood (or a dot when only
    /// other questions were answered, or a ring when nothing was).
    private func dayCell(_ day: CareReflection.Day) -> some View {
        let theme = context.theme
        return VStack(spacing: 6) {
            Text(day.letter).font(.system(size: 12, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? theme.label : theme.secondaryLabel)
            ZStack {
                Circle().fill(day.answered > 0 ? context.accent.opacity(0.18) : theme.tertiaryBackground)
                if let mood = day.mood {
                    Image(systemName: mood.symbolName).font(.system(size: 13)).foregroundStyle(context.accent)
                } else if day.answered > 0 {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(context.accent)
                }
            }
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(day.isToday ? context.accent : .clear, lineWidth: 1.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayLabel(day))
    }

    private func dayLabel(_ day: CareReflection.Day) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide))
        if day.asked == 0 { return "\(name): nothing asked" }
        return "\(name): answered \(day.answered) of \(day.asked)" + (day.mood.map { ", \($0.label)" } ?? "")
    }

    /// "Sleep · latest 8 · average 7.0", a small bar per answer, and the ends of the scale.
    private func seriesCard(_ series: CareReflection.Series) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.short).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                Spacer()
                Text(series.scores.count == 1 ? "\(series.latest) out of 10" : "latest \(series.latest) · average \(series.averageText)")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
            // Each answer as a bar with its number on top, oldest on the left
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(series.scores.enumerated()), id: \.offset) { index, score in
                    let isLatest = index == series.scores.count - 1
                    VStack(spacing: 3) {
                        Text("\(score)").font(.system(size: 11, weight: isLatest ? .bold : .regular))
                            .foregroundStyle(isLatest ? theme.label : theme.secondaryLabel)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLatest ? context.accent : context.accent.opacity(0.45))
                            .frame(width: 18, height: max(4, CGFloat(score) / 10 * 56))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 74, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(series.short) answers, oldest to newest: " + series.scores.map(String.init).joined(separator: ", "))
            HStack {
                Text("0 = \(series.lowLabel)")
                Spacer()
                Text("10 = \(series.highLabel)")
            }
            .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.tertiaryBackground))
    }
}

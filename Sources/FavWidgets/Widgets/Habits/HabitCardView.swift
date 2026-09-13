import SwiftUI
import FavWidgetsCore

/// Card: "3 / 4 done today · best streak 12" and a wrapping row of chips,
/// one per habit due today; tapping a chip toggles it in place.
struct HabitCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<HabitLog>

    var body: some View {
        let theme = context.theme
        let model = state.model
        let today = context.today
        let active = model.activeHabits
        let due = active.filter { $0.schedule.isDue(on: today, calendar: context.calendar) }

        WidgetCard(context: context, action: active.isEmpty ? addAction : nil) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.summary(summaryText(active: active, due: due), theme: theme)
                if !due.isEmpty {
                    HabitChipFlow(spacing: 6) {
                        ForEach(due) { habit in
                            chip(for: habit, done: model.isDone(habit.id, on: today), theme: theme)
                        }
                    }
                }
            }
        }
        .task { await state.loadIfNeeded() }
    }

    private var addAction: WidgetQuickAction {
        WidgetQuickAction("Add", symbolName: "plus") {
            context.track("widget_card_action", ["action": "add_habit"])
            context.openFullView()
        }
    }

    private func summaryText(active: [Habit], due: [Habit]) -> String {
        guard !active.isEmpty else { return "Add your first habit" }
        let counts = state.model.doneCount(on: context.today, calendar: context.calendar)
        let best = HabitFormatting.bestStreak(in: state.model, habits: active, today: context.today, calendar: context.calendar)
        if due.isEmpty { return "Nothing due today · best streak \(best)" }
        return "\(counts.done) / \(counts.due) done today · best streak \(best)"
    }

    private func chip(for habit: Habit, done: Bool, theme: WidgetTheme) -> some View {
        Button {
            let today = context.today
            state.update { $0.toggle(habit.id, on: today, calendar: context.calendar) }
            context.host.haptic(done ? .light : .success)
            context.track("widget_card_action", ["action": done ? "uncheck_habit" : "check_habit"])
        } label: {
            HStack(spacing: 4) {
                Image(systemName: done ? "checkmark.circle.fill" : habit.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(habit.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(done ? Color.white : theme.label)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(done ? context.accent : theme.tertiaryBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(habit.name), \(done ? "done" : "not done")")
        .accessibilityHint("Toggles completion")
    }
}

/// Wraps its children onto as many rows as needed (chips, day toggles).
struct HabitChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews: subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, width: bounds.width)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: width.isFinite ? width : maxX, height: y + rowHeight), origins)
    }
}

import SwiftUI
import FavWidgetsCore

/// Last Time (Wes, 2026-11-20): "When did I last…?" — haircut, air filter,
/// called Mom. One tap says "did it"; each tile shows how long it has been
/// and turns amber when it is due.
public struct LastTimeWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "lasttime",
        title: "Last Time",
        subtitle: "When did I last…?",
        symbolName: "clock.arrow.circlepath",
        accentHex: "#C05621",
        category: .health,
        schemaVersion: LastTimeList.schemaVersion,
        shareBlurb: "Haircut, air filter, called Mom — one tap logs it, and you always know how long it's been."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(LastTimeCardView(context: context, state: context.state(LastTimeList.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(LastTimeFullView(context: context, state: context.state(LastTimeList.self)))
    }
}

@MainActor
enum LastTimeActions {
    static let notificationType = "lasttime_due"
    static let reminderPrefix = "lasttime-"

    static func markDone(_ item: LastTimeItem, context: WidgetContext, state: WidgetStateController<LastTimeList>) {
        state.update { list in
            guard let i = list.items.firstIndex(where: { $0.id == item.id }) else { return }
            list.items[i].markDone()
        }
        context.host.haptic(.success)
        context.track("lasttime_done")
        Task { await syncReminders(state.model, calendar: context.calendar) }
    }

    static func undo(_ item: LastTimeItem, context: WidgetContext, state: WidgetStateController<LastTimeList>) {
        state.update { list in
            guard let i = list.items.firstIndex(where: { $0.id == item.id }) else { return }
            list.items[i].undoLast()
        }
        context.host.haptic(.light)
        Task { await syncReminders(state.model, calendar: context.calendar) }
    }

    /// 9 AM on the day each item comes due.
    static func syncReminders(_ list: LastTimeList, calendar: Calendar) async {
        let now = Date()
        let items = list.items.compactMap { item -> WidgetLocalReminders.Item? in
            guard let at = LastTimePlan.reminderTime(item, now: now, calendar: calendar) else { return nil }
            let since = LastTimePlan.elapsedText(since: item.lastDone, now: at, calendar: calendar).lowercased()
            return WidgetLocalReminders.Item(id: reminderPrefix + item.id, at: at, title: "⏱ \(item.name)",
                                             body: "It's been \(since). Time again?", type: notificationType)
        }
        await WidgetLocalReminders.replace(prefix: reminderPrefix, with: items)
    }
}

struct LastTimeCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<LastTimeList>

    var body: some View {
        let theme = context.theme
        let now = Date()
        let items = LastTimePlan.sorted(state.model.items, now: now, calendar: context.calendar)
        WidgetCard(context: context, action: items.isEmpty ? WidgetQuickAction("Add", symbolName: "plus") { context.openFullView() } : nil) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetUI.summary(LastTimePlan.summary(state.model.items, now: now, calendar: context.calendar), theme: theme)
                if !items.isEmpty {
                    HabitChipFlow(spacing: 6) {
                        ForEach(items.prefix(6)) { item in chip(item, now: now, theme: theme) }
                    }
                }
            }
        }
        .task { await state.loadIfNeeded() }
    }

    /// Tap = did it, right from the card.
    private func chip(_ item: LastTimeItem, now: Date, theme: WidgetTheme) -> some View {
        let status = LastTimePlan.status(item, now: now, calendar: context.calendar)
        let tint: Color = status == .overdue ? theme.danger : (status == .soon ? theme.warning : theme.tertiaryBackground)
        let onTint = status != .fine
        return Button { LastTimeActions.markDone(item, context: context, state: state) } label: {
            HStack(spacing: 4) {
                Image(systemName: item.symbolName).font(.system(size: 11, weight: .semibold))
                Text("\(item.name) · \(LastTimePlan.shortElapsed(since: item.lastDone, now: now, calendar: context.calendar))")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(onTint ? Color.white : theme.label)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(LastTimePlan.elapsedText(since: item.lastDone, now: now, calendar: context.calendar))")
        .accessibilityHint("Logs it as done now")
    }
}

struct LastTimeFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<LastTimeList>
    @State private var adding = false
    @State private var editing: LastTimeItem?
    @State private var undoable: LastTimeItem?
    @State private var undoTask: Task<Void, Never>?

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        let now = Date()
        let items = LastTimePlan.sorted(state.model.items, now: now, calendar: context.calendar)
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if items.isEmpty { empty } else {
                        Text("Tap a tile when you do it. Hold for history and settings.")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(items) { item in tile(item, now: now) }
                        }
                    }
                    WidgetUI.primaryButton("Add something to track", color: context.accent) { adding = true }
                    Text("Every \u{201C}did it\u{201D} is kept, so you can look back years later.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                .padding(16)
                .padding(.bottom, undoable == nil ? 0 : 60)
            }
            if let undoable { undoBar(undoable) }
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await state.loadIfNeeded()
            await LastTimeActions.syncReminders(state.model, calendar: context.calendar)
        }
        .sheet(isPresented: $adding) { LastTimeEditSheet(context: context, state: state, editing: nil) }
        .sheet(item: $editing) { item in LastTimeEditSheet(context: context, state: state, editing: item) }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 44)).foregroundStyle(context.accent)
            Text("When did you last change the air filter? Call Mom? Get a haircut?")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label).multilineTextAlignment(.center)
            Text("Add the things you always wonder about. One tap says \u{201C}did it\u{201D}; the tile shows how long it's been.")
                .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private func tile(_ item: LastTimeItem, now: Date) -> some View {
        let status = LastTimePlan.status(item, now: now, calendar: context.calendar)
        let bar: Color = status == .overdue ? theme.danger : (status == .soon ? theme.warning : context.accent)
        return Button { didIt(item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: item.symbolName).font(.system(size: 18, weight: .semibold)).foregroundStyle(bar)
                    Spacer()
                    Button { editing = item } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 16)).foregroundStyle(theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(item.name)")
                }
                Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).lineLimit(2)
                Text(LastTimePlan.elapsedText(since: item.lastDone, now: now, calendar: context.calendar))
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(theme.label).minimumScaleFactor(0.7).lineLimit(1)
                Text(LastTimePlan.dueText(item, now: now, calendar: context.calendar) ?? "Tap when you do it")
                    .font(.system(size: 12, weight: status == .fine ? .regular : .semibold))
                    .foregroundStyle(status == .fine ? theme.secondaryLabel : bar).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(bar).frame(height: 3).padding(.horizontal, 12).padding(.bottom, 6)
                    }
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editing = item } label: { Label("History & settings", systemImage: "list.bullet.clipboard") }
        }
        .accessibilityLabel("\(item.name), \(LastTimePlan.elapsedText(since: item.lastDone, now: now, calendar: context.calendar))")
        .accessibilityHint("Logs it as done now")
    }

    private func didIt(_ item: LastTimeItem) {
        LastTimeActions.markDone(item, context: context, state: state)
        undoTask?.cancel()
        withAnimation { undoable = item }
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { undoable = nil }
        }
    }

    private func undoBar(_ item: LastTimeItem) -> some View {
        HStack {
            Text("\(item.name) · done just now").font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            Button("Undo") {
                LastTimeActions.undo(item, context: context, state: state)
                undoTask?.cancel()
                withAnimation { undoable = nil }
            }
            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Capsule().fill(context.accent).shadow(color: .black.opacity(0.2), radius: 6, y: 2))
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Add (starters or custom) and edit (name, symbol, gap, history, delete).
struct LastTimeEditSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<LastTimeList>
    let editing: LastTimeItem?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "clock.arrow.circlepath"
    @State private var everyDays: Int?
    @State private var startDoneNow = true
    @State private var confirmDelete = false

    private var theme: WidgetTheme { context.theme }
    private var current: LastTimeItem? { editing.flatMap { e in state.model.items.first { $0.id == e.id } } }

    var body: some View {
        WidgetSheet(title: editing == nil ? "Track something" : "Edit", theme: theme,
                    confirm: ("Save", !name.trimmingCharacters(in: .whitespaces).isEmpty, save)) {
            Form {
                if editing == nil {
                    Section("Common ones") {
                        HabitChipFlow(spacing: 6) {
                            ForEach(LastTimePlan.starters, id: \.name) { s in
                                let taken = state.model.items.contains { $0.name.caseInsensitiveCompare(s.name) == .orderedSame }
                                Button {
                                    name = s.name; symbol = s.symbolName; everyDays = s.everyDays
                                } label: {
                                    Label(s.name, systemImage: s.symbolName).font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(taken ? theme.secondaryLabel : (name == s.name ? .white : theme.label))
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Capsule().fill(name == s.name ? context.accent : theme.tertiaryBackground))
                                }
                                .buttonStyle(.plain).disabled(taken)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    TextField("What is it? (e.g. Haircut)", text: $name)
                    Picker("Remind me", selection: $everyDays) {
                        ForEach(LastTimePlan.gapChoices, id: \.self) { Text(LastTimePlan.gapTitle($0)).tag($0) }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LastTimePlan.symbolChoices, id: \.self) { s in
                                Button { symbol = s } label: {
                                    Image(systemName: s).font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(symbol == s ? .white : theme.label)
                                        .frame(width: 36, height: 36)
                                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(symbol == s ? context.accent : theme.tertiaryBackground))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if editing == nil { Toggle("I just did it", isOn: $startDoneNow) }
                }
                if let item = current {
                    Section("History") {
                        if item.history.isEmpty { Text("Not done yet").foregroundStyle(theme.secondaryLabel) }
                        ForEach(Array(item.history.reversed().enumerated()), id: \.offset) { _, date in
                            Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        }
                        .onDelete { offsets in
                            state.update { list in
                                guard let i = list.items.firstIndex(where: { $0.id == item.id }) else { return }
                                var reversed = Array(list.items[i].history.reversed())
                                reversed.remove(atOffsets: offsets)
                                list.items[i].history = reversed.reversed()
                                list.items[i].updatedAt = Date()
                            }
                        }
                    }
                    Section {
                        Button("Delete \(item.name)", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .onAppear {
                if let item = editing { name = item.name; symbol = item.symbolName; everyDays = item.everyDays }
            }
            .confirmationDialog("Delete \(name) and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let item = editing { state.update { $0.items.removeAll { $0.id == item.id } } }
                    Task { await LastTimeActions.syncReminders(state.model, calendar: context.calendar) }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        state.update { list in
            if let e = editing, let i = list.items.firstIndex(where: { $0.id == e.id }) {
                list.items[i].name = trimmed; list.items[i].symbolName = symbol; list.items[i].everyDays = everyDays
                list.items[i].updatedAt = Date()
            } else {
                var item = LastTimeItem(name: trimmed, symbolName: symbol, everyDays: everyDays)
                if startDoneNow { item.markDone() }
                list.items.append(item)
            }
        }
        context.track(editing == nil ? "lasttime_added" : "lasttime_edited")
        Task { await LastTimeActions.syncReminders(state.model, calendar: context.calendar) }
        dismiss()
    }
}

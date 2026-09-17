import SwiftUI
import FavWidgetsCore

/// Full screen: the whole watchlist as Yahoo rows with swipe-to-remove and
/// drag reordering, a status line ("At close: 4:00 PM EDT"), search to add,
/// and a detail sheet per symbol.
struct StocksFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<Watchlist>
    @ObservedObject var quotes: StockQuoteStore

    @State private var addTarget: AddTarget?
    @State private var selected: WatchlistEntry?
    @State private var listPrompt: ListPrompt?
    @State private var listName = ""
    @State private var showListReorder = false

    private struct AddTarget: Identifiable { let id: UUID }
    private enum ListPrompt: Identifiable {
        case create
        case rename(UUID, String)
        var id: String { if case .rename(let id, _) = self { return id.uuidString } else { return "create" } }
    }

    var body: some View {
        let theme = context.theme
        VStack(spacing: 0) {
            header(theme: theme)
            list(theme: theme)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    #if os(iOS)
                    if !state.model.entries.isEmpty { EditButton() }
                    #endif
                    Button { openSearch(for: state.model.lists.first?.id) } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Add a symbol")
                }
                .foregroundStyle(context.accent)
            }
        }
        .task {
            await state.loadIfNeeded()
            await quotes.refresh(symbols: MarketIndexes.symbols + MarketExtras.symbols + state.model.symbols)
            if quotes.pendingAddRequest {
                quotes.pendingAddRequest = false
                openSearch(for: state.model.lists.first?.id)
            }
            if let symbol = quotes.pendingDetailSymbol {
                quotes.pendingDetailSymbol = nil
                selected = (MarketIndexes.entries + MarketExtras.entries + state.model.entries).first { $0.symbol == symbol }
            }
        }
        .refreshable { await quotes.refresh(symbols: MarketIndexes.symbols + MarketExtras.symbols + state.model.symbols, force: true) }
        .onAppear { quotes.startPolling { MarketIndexes.symbols + MarketExtras.symbols + state.model.symbols } }
        .onDisappear { quotes.stopPolling() }
        .sheet(item: $addTarget) { target in
            StockSearchView(context: context, existing: Set(state.model.list(id: target.id)?.symbols ?? [])) { hit in
                add(hit, to: target.id)
            }
        }
        .sheet(isPresented: $showListReorder) {
            StockListReorderView(context: context, state: state)
        }
        .alert(promptTitle, isPresented: Binding(get: { listPrompt != nil }, set: { if !$0 { listPrompt = nil } })) {
            TextField("List name", text: $listName)
            Button(promptButton, action: commitListPrompt)
            Button("Cancel", role: .cancel) { listPrompt = nil }
        } message: {
            Text("Group the stocks you follow — Tech, Crypto, Retirement…")
        }
        .sheet(item: $selected) { entry in
            StockDetailView(context: context, entry: entry, quotes: quotes) {
                remove(entry.symbol)
                selected = nil
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(theme: WidgetTheme) -> some View {
        HStack(spacing: 8) {
            WidgetSyncBadge(state: state.syncState, theme: theme)
            if let status = StockStatusLine.text(state: quotes.marketState(), asOf: quotes.asOf,
                                                 timezone: quotes.headerTimezone) {
                HStack(spacing: 5) {
                    if quotes.marketState() == .live {
                        Circle().fill(StockPalette.up).frame(width: 7, height: 7)
                    }
                    Text(status)
                }
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            if quotes.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let error = quotes.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.warning)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private func list(theme: WidgetTheme) -> some View {
        List {
            Section {
                ForEach(MarketIndexes.entries) { entry in
                    Button { open(entry) } label: {
                        StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.background)
                    .listRowSeparatorTint(theme.separator)
                    .moveDisabled(true)
                    .deleteDisabled(true)
                }
            } header: {
                Text("Indexes").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
            }

            ForEach(state.model.lists) { list in
                Section {
                    if list.isCollapsed {
                        EmptyView()
                    } else {
                    if list.entries.isEmpty {
                        Text("Nothing here yet — tap Add Symbol.")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.secondaryLabel)
                            .padding(.vertical, 6)
                            .listRowBackground(theme.background)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                    }
                    ForEach(list.entries) { entry in
                        Button { open(entry) } label: {
                            StockRow(entry: entry, quote: quotes.quote(entry.symbol), theme: theme)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.background)
                        .listRowSeparatorTint(theme.separator)
                    }
                    .onDelete { offsets in
                        let symbols = offsets.compactMap { list.entries.indices.contains($0) ? list.entries[$0].symbol : nil }
                        symbols.forEach { remove($0, from: list.id) }
                    }
                    .onMove { source, destination in
                        state.update { $0.move(fromOffsets: source, toOffset: destination, in: list.id) }
                        context.track("stocks_reordered")
                    }

                    // Yahoo ends its list with this row; it also means adding never
                    // depends on the navigation bar bridging the toolbar button.
                    Button { openSearch(for: list.id) } label: {
                        Label("Add Symbol", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(context.theme.accent)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.background)
                    .moveDisabled(true)
                    .deleteDisabled(true)
                    }
                } header: {
                    HStack(spacing: 8) {
                        // Tap the name/chevron to fold the list; the count stands in for the rows
                        Button {
                            state.update { $0.setCollapsed(!list.isCollapsed, listId: list.id) }
                            context.host.haptic(.light)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .rotationEffect(.degrees(list.isCollapsed ? -90 : 0))
                                Text(list.name).font(.system(size: 12, weight: .semibold))
                                if list.isCollapsed {
                                    Text("· \(list.entries.count)").font(.system(size: 12))
                                }
                            }
                            .foregroundStyle(theme.secondaryLabel)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(list.isCollapsed ? "Expand \(list.name)" : "Collapse \(list.name)")
                        Spacer()
                        Menu {
                            Button { listName = list.name; listPrompt = .rename(list.id, list.name) } label: { Label("Rename", systemImage: "pencil") }
                            Button { state.update { $0.moveList(list.id, by: -1) } } label: { Label("Move up", systemImage: "arrow.up") }
                                .disabled(state.model.lists.first?.id == list.id)
                            Button { state.update { $0.moveList(list.id, by: 1) } } label: { Label("Move down", systemImage: "arrow.down") }
                                .disabled(state.model.lists.last?.id == list.id)
                            Button { showListReorder = true } label: { Label("Reorder lists…", systemImage: "arrow.up.arrow.down") }
                            Button(role: .destructive) { deleteList(list.id) } label: { Label("Delete list", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.secondaryLabel)
                                .frame(width: 32, height: 24)
                        }
                        .accessibilityLabel("\(list.name) options")
                    }
                }
            }

            Section {
                Button { listName = ""; listPrompt = .create } label: {
                    Label("New List", systemImage: "folder.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(context.theme.accent)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.background)
                .moveDisabled(true)
                .deleteDisabled(true)
                .disabled(state.model.lists.count >= Watchlist.maxLists)
            } footer: {
                Text("Quotes by Yahoo Finance. Prices may be delayed.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Lists

    private var promptTitle: String {
        if case .rename = listPrompt { return "Rename list" } else { return "New list" }
    }
    private var promptButton: String {
        if case .rename = listPrompt { return "Save" } else { return "Create" }
    }

    private func commitListPrompt() {
        let name = listName
        switch listPrompt {
        case .create:
            var created: UUID?
            state.update { created = $0.addList(named: name) }
            if created != nil { context.host.haptic(.success); context.track("stocks_list_created") }
        case .rename(let id, _):
            state.update { $0.renameList(id, to: name) }
            context.track("stocks_list_renamed")
        case nil:
            break
        }
        listPrompt = nil
        listName = ""
    }

    private func deleteList(_ id: UUID) {
        let symbols = state.model.list(id: id)?.symbols ?? []
        state.update { $0.deleteList(id) }
        // Drop cached quotes nobody references any more
        for symbol in symbols where !state.model.contains(symbol) { quotes.forget(symbol) }
        context.host.haptic(.light)
        context.track("stocks_list_deleted")
    }

    private func openSearch(for listId: UUID?) {
        context.track("stocks_search_opened")
        // No list yet: make the default one so the symbol has somewhere to go
        var target = listId
        if target == nil {
            state.update { target = $0.addList(named: Watchlist.defaultListName) }
        }
        guard let target else { return }
        addTarget = AddTarget(id: target)
    }

    private func open(_ entry: WatchlistEntry) {
        context.track("stocks_detail_opened", ["symbol": entry.symbol])
        selected = entry
    }

    private func add(_ hit: StockSearchHit, to listId: UUID) {
        var added = false
        state.update { added = $0.add(hit.entry, to: listId) }
        guard added else {
            let name = state.model.list(id: listId)?.name ?? Watchlist.defaultListName
            context.host.presentAlert(WidgetAlert(title: "Already on your list",
                                                  message: state.model.list(id: listId)?.contains(hit.symbol) == true
                                                      ? "\(hit.symbol) is already in \(name)."
                                                      : "A list holds up to \(Watchlist.maxEntries) symbols."))
            return
        }
        context.host.haptic(.success)
        context.track("stocks_symbol_added", ["symbol": hit.symbol])
        Task { await quotes.fetch(hit.symbol) }
    }

    private func remove(_ symbol: String, from listId: UUID? = nil) {
        state.update { $0.remove(symbol, from: listId) }
        if !state.model.contains(symbol) { quotes.forget(symbol) }
        context.host.haptic(.light)
        context.track("stocks_symbol_removed", ["symbol": symbol])
    }
}

// MARK: - Reorder lists sheet

/// Drag handles for the lists themselves (sections can't be dragged in
/// place). Whole lists move; their rows are untouched.
private struct StockListReorderView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<Watchlist>
    @Environment(\.dismiss) private var dismiss

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reorder lists").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label)
                Spacer()
                Button("Done") { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.primary)
            }
            .padding(20)
            List {
                ForEach(state.model.lists) { list in
                    HStack {
                        Text(list.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                        Spacer()
                        Text("\(list.entries.count) \(list.entries.count == 1 ? "stock" : "stocks")")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    }
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    state.update { $0.moveLists(fromOffsets: source, toOffset: destination) }
                    context.host.haptic(.light)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
        }
        .background(theme.background.ignoresSafeArea())
    }
}

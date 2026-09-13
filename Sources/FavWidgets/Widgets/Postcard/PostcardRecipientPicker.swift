import SwiftUI
import FavWidgetsCore

/// Searchable list of the user's connections, shown in a sheet from the
/// "To" row. Loads on appear; empty and error states offer a Retry.
struct PostcardRecipientPicker: View {
    let context: WidgetContext
    let selectedId: String?
    let onSelect: (WidgetContact) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var connections: [WidgetContact] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var query = ""

    private var filtered: [WidgetContact] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return connections }
        return connections.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            content
                .widgetInlineNavigationTitle("Send to")
                .searchable(text: $query, prompt: "Search connections")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        let theme = context.theme
        if isLoading && connections.isEmpty {
            WidgetStatusView(theme: theme, isLoading: true, message: nil)
        } else if let errorMessage {
            statusPanel(symbol: "wifi.exclamationmark", title: "Couldn't load your connections", detail: errorMessage, theme: theme)
        } else if hasLoaded && connections.isEmpty {
            statusPanel(symbol: "person.2", title: "No connections yet",
                        detail: "Connect with people in FavCircles and they'll show up here.", theme: theme)
        } else if filtered.isEmpty {
            statusPanel(symbol: "magnifyingglass", title: "No matches", detail: "Try a different name.", theme: theme, showsRetry: false)
        } else {
            List(filtered) { contact in
                Button {
                    onSelect(contact)
                    dismiss()
                } label: {
                    PostcardContactRow(contact: contact, theme: theme, accent: context.accent,
                                       isSelected: contact.id == selectedId)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func statusPanel(symbol: String, title: String, detail: String, theme: WidgetTheme, showsRetry: Bool = true) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(theme.secondaryLabel)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.label)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
            if showsRetry {
                Button("Retry") { Task { await load() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(context.accent)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            connections = try await context.host.fetchConnections()
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        isLoading = false
    }
}

/// Avatar + name row; also used on the "To" row of the compose screen.
struct PostcardContactRow: View {
    let contact: WidgetContact
    let theme: WidgetTheme
    let accent: Color
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            PostcardAvatar(url: contact.avatarURL, name: contact.displayName, theme: theme, accent: accent)
            Text(contact.displayName)
                .font(.system(size: 16))
                .foregroundStyle(theme.label)
                .lineLimit(1)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PostcardAvatar: View {
    let url: URL?
    let name: String
    let theme: WidgetTheme
    let accent: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.18))
            Text(name.first.map { String($0).uppercased() } ?? "?")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(accent)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }
}

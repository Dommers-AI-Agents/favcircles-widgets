import SwiftUI
import FavWidgetsCore

/// One month's rows of the "Sent" history, newest first. A child view so
/// each on-demand month owns its own `@ObservedObject`.
struct PostcardMonthRows: View {
    let context: WidgetContext
    let month: MonthKey
    @ObservedObject var controller: WidgetStateController<PostcardMonth>
    let onSelect: (PostcardRecord) -> Void

    private var records: [PostcardRecord] {
        controller.model.sent.sorted { $0.sentAt > $1.sentAt }
    }

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 8) {
            if controller.syncState == .loading && !controller.hasLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(PostcardMonthRows.title(for: month, calendar: context.calendar))…")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryLabel)
                }
            } else if !records.isEmpty {
                Text(PostcardMonthRows.title(for: month, calendar: context.calendar))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                ForEach(records) { record in
                    Button { onSelect(record) } label: {
                        PostcardRecordRow(record: record, theme: theme, accent: context.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await controller.loadIfNeeded() }
    }

    static func title(for month: MonthKey, calendar: Calendar) -> String {
        let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }
}

struct PostcardRecordRow: View {
    let record: PostcardRecord
    let theme: WidgetTheme
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent.opacity(0.15))
                Image(systemName: "envelope.fill").foregroundStyle(accent)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.recipientName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let place = record.place?.name, !place.isEmpty { parts.append(place) }
        parts.append(record.sentAt.formatted(date: .abbreviated, time: .shortened))
        parts.append(PostcardTemplate.resolve(record.templateId).name)
        return parts.joined(separator: " · ")
    }
}

/// Tap-through detail for one sent postcard.
struct PostcardRecordDetail: View {
    let context: WidgetContext
    let record: PostcardRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = record.imageURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.tertiaryBackground)
                                    ProgressView()
                                }
                                .aspectRatio(PostcardTemplate.aspectRatio, contentMode: .fit)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    detailRow("To", record.recipientName, theme: theme)
                    if let place = record.place?.name, !place.isEmpty {
                        detailRow("From", place, theme: theme)
                    }
                    detailRow("Sent", record.sentAt.formatted(date: .long, time: .shortened), theme: theme)
                    detailRow("Template", PostcardTemplate.resolve(record.templateId).name, theme: theme)
                    if !record.message.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            WidgetUI.header("Message", theme: theme)
                            Text(record.message)
                                .font(.system(size: 15))
                                .foregroundStyle(theme.label)
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Postcard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, theme: WidgetTheme) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryLabel)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(theme.label)
            Spacer()
        }
    }
}

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
        // A mailed card's status is the thing worth reading in a list; the
        // template name is not.
        if let order = record.mailOrder { return order.displayStatus }
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

    /// The live order, refreshed on appear. The stored copy is a snapshot
    /// from send time, and the whole point of the cancel window is that it
    /// changes underneath — a stale "cancel free until it prints" is worse
    /// than none.
    @State private var order: PostcardMailOrder?
    @State private var isCanceling = false
    @State private var cancelError: String?

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
                    if let order = order ?? record.mailOrder {
                        mailSection(order, theme: theme)
                    }
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
            .task { await refreshOrder() }
            .widgetInlineNavigationTitle("Postcard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Printed and mailed

    @ViewBuilder
    private func mailSection(_ order: PostcardMailOrder, theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("Printed postcard", theme: theme)
            Text(order.displayStatus)
                .font(.system(size: 14))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(order.priceText) · order \(order.orderId.prefix(8))")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
            if order.status.isCancelable {
                Button {
                    Task { await cancel(order) }
                } label: {
                    Text(isCanceling ? "Canceling…" : "Cancel before it prints")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.danger)
                }
                .disabled(isCanceling)
            }
            if let cancelError {
                Text(cancelError).font(.system(size: 12)).foregroundStyle(theme.danger)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
    }

    private func refreshOrder() async {
        guard let stored = record.mailOrder else { return }
        guard let live = try? await PostcardMail.orders(context: context)
            .first(where: { $0.orderId == stored.orderId })?.asRecordOrder else { return }
        order = live
        persist(live)
    }

    private func cancel(_ order: PostcardMailOrder) async {
        guard !isCanceling else { return }
        isCanceling = true
        cancelError = nil
        defer { isCanceling = false }
        do {
            let updated = try await PostcardMail.cancel(context: context, orderId: order.orderId).asRecordOrder
            self.order = updated
            persist(updated)
            context.host.haptic(.success)
        } catch {
            // Most often "already on its way to print" — the server decides
            // on status, not the clock.
            cancelError = error.localizedDescription
        }
    }

    /// Writes the live status back into history so the row matches.
    private func persist(_ updated: PostcardMailOrder) {
        let month = MonthKey(record.sentAt)
        context.month(PostcardMonth.self, month).update { stored in
            for index in stored.sent.indices where stored.sent[index].mailOrder?.orderId == updated.orderId {
                stored.sent[index].mailOrder = updated
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

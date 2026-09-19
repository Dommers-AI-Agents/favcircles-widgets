import SwiftUI
import FavWidgetsCore

extension PostcardFullView {
    /// Tops up the sent history with printed-card orders the server knows
    /// and this phone doesn't (see `PostcardHistoryReconciler`), then opens
    /// the card a push tap asked for, if any.
    func reconcileMailHistory() async {
        await settings.loadIfNeeded()
        await currentMonth.loadIfNeeded()
        await previousMonth.loadIfNeeded()
        guard let orders = try? await PostcardMail.orders(context: context) else { return }
        let known = Set((currentMonth.model.sent + previousMonth.model.sent).map(\.messageId))
        let missing = PostcardHistoryReconciler.missingRecords(
            orders: orders.map(\.asRecordOrder), knownMessageIds: known,
            templateId: settings.model.lastTemplateId, calendar: context.calendar)
        for (month, rows) in Dictionary(grouping: missing, by: \.month) {
            let controller = context.month(PostcardMonth.self, month)
            await controller.loadIfNeeded()
            let present = Set(controller.model.sent.map(\.messageId))
            let fresh = rows.map(\.record).filter { !present.contains($0.messageId) }
            guard !fresh.isEmpty else { continue }
            controller.update { $0.sent.append(contentsOf: fresh) }
            if !extraMonths.contains(month), month != context.currentMonth, month != context.currentMonth.previous {
                extraMonths.append(month)
            }
        }
    }

    /// The push said "your postcard is printing"; show that card, with its
    /// live status, rather than a blank composer.
    func openLaunchedOrder() {
        guard let orderId = context.launchPostcardOrderId else { return }
        context.launchPostcardOrderId = nil
        let messageId = "mail:\(orderId)"
        let months = [currentMonth, previousMonth] + extraMonths.map { context.month(PostcardMonth.self, $0) }
        guard let record = months.lazy.compactMap({ $0.model.sent.first { $0.messageId == messageId } }).first else { return }
        selectedRecord = record
    }
}

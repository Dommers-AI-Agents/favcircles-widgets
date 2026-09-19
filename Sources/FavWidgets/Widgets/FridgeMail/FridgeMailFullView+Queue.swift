import SwiftUI
import PhotosUI
import FavWidgetsCore

extension FridgeMailFullView {
    func nextCard(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Next card", theme: theme)
            if let next = plan.nextItem {
                FridgeMailPreview(item: next, familyName: plan.familyName, calendar: context.calendar)
            }
            Text(FridgeMailCopy.nextSendLine(plan, calendar: context.calendar))
                .font(.system(size: 13))
                .foregroundStyle(plan.entitlement.covered < plan.recipients.count || plan.isPaused ? theme.warning : theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func queueSection(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        let pending = plan.pending
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header(pending.isEmpty ? "Drawings" : "Drawings · \(pending.count) waiting", theme: theme)
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    addLabel("Choose photo", symbol: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                #if os(iOS)
                if PostcardCameraPicker.isAvailable {
                    Button { showCamera = true } label: { addLabel("Snap a drawing", symbol: "camera.fill") }
                        .buttonStyle(.plain)
                }
                #endif
            }
            ForEach(Array(pending.enumerated()), id: \.element.id) { index, item in
                queueRow(item, isNext: index == 0, pending: pending)
            }
            if pending.isEmpty {
                Text("Add a few at once so there's always one waiting for \(FridgeMailCopy.weekdayName(plan.weekday, calendar: context.calendar)).")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func addLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(context.accent)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.12)))
    }

    func queueRow(_ item: FridgeMailQueueItem, isNext: Bool, pending: [FridgeMailQueueItem]) -> some View {
        let theme = context.theme
        return HStack(spacing: 12) {
            FridgeMailThumb(url: item.imageURL, width: 60, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.childName.isEmpty ? "Drawing" : item.childName)
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                    if isNext {
                        Text("NEXT").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(context.accent))
                    }
                }
                Text(item.note.isEmpty ? "Added \(item.addedAt.formatted(date: .abbreviated, time: .omitted))" : item.note)
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
            }
            Spacer()
            Menu {
                if !isNext {
                    Button { moveToTop(item, pending: pending) } label: { Label("Mail this one next", systemImage: "arrow.up.to.line") }
                }
                Button(role: .destructive) { remove(item) } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(theme.secondaryLabel)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
    }

    var sentSection: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            if !store.cards.isEmpty {
                WidgetUI.header("Mailed", theme: theme)
                ForEach(store.cards) { card in
                    HStack(spacing: 12) {
                        FridgeMailThumb(url: card.imageURL, width: 60, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.childName.isEmpty ? (card.recipientName ?? "Card") : "\(card.childName) → \(card.recipientName ?? "Grandma")")
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                            Text(FridgeMailCopy.cardStatus(card.status, recipientName: card.recipientName))
                                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                            Text(card.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                }
            }
        }
    }
}

import SwiftUI
import PhotosUI
import FavWidgetsCore

extension FridgeMailFullView {
    func recipientsSection(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Grandparents", theme: theme)
            ForEach(plan.recipients) { recipient in
                HStack(spacing: 12) {
                    // Tap the person to change their name or address.
                    Button { recipientSheet = RecipientSheet(recipient: recipient) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(context.accent.opacity(0.15))
                                Image(systemName: "house.fill").foregroundStyle(context.accent)
                            }
                            .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipient.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                                Text(recipient.address.oneLine).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                                Text("Tap to edit").font(.system(size: 11)).foregroundStyle(context.accent)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                    Button { removeRecipient(recipient) } label: {
                        Image(systemName: "minus.circle").font(.system(size: 18)).foregroundStyle(theme.secondaryLabel)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            }
            if plan.recipients.count < 3 {
                Button { recipientSheet = .add } label: { addLabel(plan.recipients.isEmpty ? "Add a grandparent" : "Add another", symbol: "plus") }
                    .buttonStyle(.plain)
            } else {
                Text("Three is the most Fridge Mail sends each week.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    func scheduleSection(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Every week", theme: theme)
            HStack {
                Text("Mails on").font(.system(size: 14)).foregroundStyle(theme.label)
                Spacer()
                Menu {
                    ForEach(0..<7, id: \.self) { day in
                        Button(FridgeMailCopy.weekdayName(day, calendar: context.calendar)) { setWeekday(day) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(FridgeMailCopy.weekdayName(plan.weekday, calendar: context.calendar))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
            }
            HStack(spacing: 8) {
                Text("Signed").font(.system(size: 14)).foregroundStyle(theme.label)
                TextField("the Sgrois", text: $familyNameDraft)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .onSubmit { saveFamilyName() }
                if familyNameDraft.trimmingCharacters(in: .whitespaces) != plan.familyName {
                    Button("Save") { saveFamilyName() }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
                }
            }
            Text("Printed on the back as \"\(FridgeMailCopy.signature(familyName: familyNameDraft))\".")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            Button {
                run("pause") { try await FridgeMailAPI.updatePlan(context: context, status: plan.isPaused ? "active" : "paused") }
            } label: {
                Text(plan.isPaused ? "Resume weekly cards" : "Pause weekly cards")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(plan.isPaused ? context.accent : theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(busy != nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    func planSection(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        let canPay = context.host.supportsPayment && (store.config?.isUsable ?? false)
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Cards", theme: theme)
            Text(FridgeMailCopy.planStatus(plan, calendar: context.calendar))
                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)

            if let sub = plan.subscription, sub.isActive {
                if sub.cancelAtPeriodEnd {
                    Button("Keep my subscription") { run("resume") { try await FridgeMailAPI.resumeSubscription(context: context) } }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent).disabled(busy != nil)
                } else {
                    Button("Cancel subscription") { run("cancel") { try await FridgeMailAPI.cancelSubscription(context: context) } }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.secondaryLabel).disabled(busy != nil)
                }
            } else if canPay {
                subscribeBlock(plan)
            }

            if canPay {
                packsBlock(plan)
            } else if store.config != nil {
                Text("Buying cards needs Apple Pay on this device.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    func subscribeBlock(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        let n = max(1, plan.recipients.count)
        let monthly = PostcardMailOrder.price(cents: plan.subscriptionPriceCents * n)
        return VStack(alignment: .leading, spacing: 6) {
            // Apple's button, not ours: this is a purchase, and Guideline 4.9
            // wants Apple Pay's own branding on it.
            Text("Subscribe · \(monthly)/month")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
            WidgetApplePayButton(.subscribe) { subscribe(plan) }
                .disabled(busy != nil)
            if busy == "subscribe" {
                Text("Opening Apple Pay…")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
            Text(n == 1
                 ? "One card every week to your grandparent, \(FridgeMailCopy.subscriptionPriceText) a month. Cancel anytime."
                 : "One card every week to each of \(n) grandparents, \(FridgeMailCopy.subscriptionPriceText) a month each. Cancel anytime.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func packsBlock(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            Text(plan.isSubscribed ? "Or top up with a pack" : "Or buy a pack of cards")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.label)
            HStack(spacing: 8) {
                ForEach(plan.packs) { pack in
                    Button { selectedPackId = pack.id } label: {
                        VStack(spacing: 2) {
                            Text(pack.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                            Text(pack.priceText).font(.system(size: 13)).foregroundStyle(context.accent)
                            Text(pack.perCardText).font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.background))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selectedPackId == pack.id || busy == pack.id ? context.accent : theme.separator,
                                    lineWidth: selectedPackId == pack.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                }
            }
            // Picking a pack no longer charges on the spot — the tiles choose,
            // Apple's button buys. 4.9 again: the purchase tap is Apple's.
            if let pack = plan.packs.first(where: { $0.id == selectedPackId }) {
                WidgetApplePayButton(.buy) { buy(pack) }
                    .disabled(busy != nil)
            }
            Text("A pack covers one card per grandparent per week. Cards never expire.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }
}

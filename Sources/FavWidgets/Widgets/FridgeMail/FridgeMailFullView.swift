import SwiftUI
import PhotosUI
import FavWidgetsCore

/// The whole of Fridge Mail on one screen: what goes out next, the queue
/// of drawings, the grandparents, the weekly schedule, how it's paid for,
/// and what has already been mailed.
struct FridgeMailFullView: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pickedImage: PostcardPlatformImage?
    @State private var showAddSheet = false
    @State private var showRecipientSheet = false
    /// Which button is mid-flight, so the rest stay tappable but that one
    /// can't be double-tapped.
    @State private var busy: String?
    @State private var familyNameDraft = ""

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plan = store.plan {
                    if plan.isEmpty { explainer }
                    nextCard(plan)
                    queueSection(plan)
                    recipientsSection(plan)
                    scheduleSection(plan)
                    planSection(plan)
                    sentSection
                } else if let error = store.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.system(size: 14)).foregroundStyle(theme.danger)
                        Button("Try again") { Task { await store.load(context: context) } }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading your Fridge Mail…").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("Fridge Mail")
        .task {
            await store.loadIfNeeded(context: context)
            familyNameDraft = store.plan?.familyName ?? ""
        }
        .onChange(of: store.plan?.familyName) { name in
            if let name, familyNameDraft.isEmpty { familyNameDraft = name }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .onChange(of: pickedImage) { image in
            if image != nil { showAddSheet = true }
        }
        .widgetCameraCover(isPresented: $showCamera) {
            #if os(iOS)
            PostcardCameraPicker(image: $pickedImage).ignoresSafeArea()
            #endif
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { pickedImage = nil; photoItem = nil }) {
            if let image = pickedImage {
                FridgeMailAddSheet(context: context, store: store, image: image)
            }
        }
        .sheet(isPresented: $showRecipientSheet) {
            FridgeMailRecipientSheet(context: context, store: store)
        }
    }

    // MARK: - Explainer

    private var explainer: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            Text("Every week, a real postcard of your kid's latest drawing lands in Grandma's mailbox. You add the drawings; we print and mail them.")
                .font(.system(size: 15))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            step(1, "Add a grandparent", "Name and address. Up to three.")
            step(2, "Add drawings", "Snap them with the camera or pick from your photos. Add a few so there's always one waiting.")
            step(3, "We mail one a week", "Printed on a 4×6 postcard with the child's name, the date and your note on the back.")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FridgeMailCanvasView.cream))
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(context.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridgeMailCanvasView.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(FridgeMailCanvasView.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Next card

    private func nextCard(_ plan: FridgeMailPlan) -> some View {
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

    // MARK: - Queue

    private func queueSection(_ plan: FridgeMailPlan) -> some View {
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

    private func addLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(context.accent)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.12)))
    }

    private func queueRow(_ item: FridgeMailQueueItem, isNext: Bool, pending: [FridgeMailQueueItem]) -> some View {
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

    // MARK: - Recipients

    private func recipientsSection(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Grandparents", theme: theme)
            ForEach(plan.recipients) { recipient in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(context.accent.opacity(0.15))
                        Image(systemName: "house.fill").foregroundStyle(context.accent)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipient.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                        Text(recipient.address.oneLine).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                    }
                    Spacer()
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
                Button { showRecipientSheet = true } label: { addLabel(plan.recipients.isEmpty ? "Add a grandparent" : "Add another", symbol: "plus") }
                    .buttonStyle(.plain)
            } else {
                Text("Three is the most Fridge Mail sends each week.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    // MARK: - Schedule

    private func scheduleSection(_ plan: FridgeMailPlan) -> some View {
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

    // MARK: - Plan (money)

    private func planSection(_ plan: FridgeMailPlan) -> some View {
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

    private func subscribeBlock(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        let n = max(1, plan.recipients.count)
        let monthly = PostcardMailOrder.price(cents: plan.subscriptionPriceCents * n)
        return VStack(alignment: .leading, spacing: 6) {
            WidgetUI.primaryButton(busy == "subscribe" ? "Opening Apple Pay…" : "Subscribe · \(monthly)/month", color: context.accent) {
                subscribe(plan)
            }
            .disabled(busy != nil)
            Text(n == 1
                 ? "One card every week to your grandparent, \(FridgeMailCopy.subscriptionPriceText) a month. Cancel anytime."
                 : "One card every week to each of \(n) grandparents, \(FridgeMailCopy.subscriptionPriceText) a month each. Cancel anytime.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func packsBlock(_ plan: FridgeMailPlan) -> some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 8) {
            Text(plan.isSubscribed ? "Or top up with a pack" : "Or buy a pack of cards")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.label)
            HStack(spacing: 8) {
                ForEach(plan.packs) { pack in
                    Button { buy(pack) } label: {
                        VStack(spacing: 2) {
                            Text(pack.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.label)
                            Text(pack.priceText).font(.system(size: 13)).foregroundStyle(context.accent)
                            Text(pack.perCardText).font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.background))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(busy == pack.id ? context.accent : theme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                }
            }
            Text("A pack covers one card per grandparent per week. Cards never expire.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    // MARK: - Sent

    private var sentSection: some View {
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

    // MARK: - Actions

    private func run(_ key: String, _ op: @escaping () async throws -> FridgeMailPlan?) {
        guard busy == nil else { return }
        busy = key
        Task {
            defer { busy = nil }
            do {
                if let plan = try await op() { store.apply(plan) }
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Fridge Mail", message: error.localizedDescription))
            }
        }
    }

    private func setWeekday(_ day: Int) {
        context.track("fridgemail_weekday", ["weekday": "\(day)"])
        run("weekday") { try await FridgeMailAPI.updatePlan(context: context, weekday: day, timezone: TimeZone.current.identifier) }
    }

    private func saveFamilyName() {
        let name = familyNameDraft.trimmingCharacters(in: .whitespaces)
        run("family") { try await FridgeMailAPI.updatePlan(context: context, familyName: name) }
    }

    private func moveToTop(_ item: FridgeMailQueueItem, pending: [FridgeMailQueueItem]) {
        let ids = [item.id] + pending.map(\.id).filter { $0 != item.id }
        run("reorder") { try await FridgeMailAPI.reorderQueue(context: context, ids: ids) }
    }

    private func remove(_ item: FridgeMailQueueItem) {
        run("remove") { try await FridgeMailAPI.removeQueued(context: context, id: item.id) }
    }

    private func removeRecipient(_ recipient: FridgeMailRecipient) {
        run("recipient") { try await FridgeMailAPI.removeRecipient(context: context, id: recipient.id) }
    }

    private func buy(_ pack: FridgeMailPack) {
        guard let config = store.config else { return }
        context.track("fridgemail_pack_tap", ["pack": pack.id])
        run(pack.id) {
            let plan = try await FridgeMailAPI.purchasePack(context: context, pack: pack, config: config)
            if plan != nil { context.host.haptic(.success) }
            return plan
        }
    }

    private func subscribe(_ plan: FridgeMailPlan) {
        guard let config = store.config else { return }
        context.track("fridgemail_subscribe_tap")
        run("subscribe") {
            let updated = try await FridgeMailAPI.subscribe(context: context, plan: plan, config: config)
            if updated != nil { context.host.haptic(.success) }
            return updated
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = PostcardPlatformImage(data: data) else {
                context.host.presentAlert(WidgetAlert(title: "Couldn't load photo", message: "That photo couldn't be read. Try another one."))
                return
            }
            pickedImage = image
            context.host.haptic(.light)
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't load photo", message: error.localizedDescription))
        }
    }
}

// MARK: - Pieces

/// A small server image with the cream card behind it while it loads.
struct FridgeMailThumb: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .background(FridgeMailCanvasView.cream)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Front and back of the card that goes out next, as it will print.
struct FridgeMailPreview: View {
    let item: FridgeMailQueueItem
    let familyName: String
    let calendar: Calendar

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: item.imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    ZStack {
                        FridgeMailCanvasView.cream
                        ProgressView().controlSize(.small)
                    }
                    .aspectRatio(1.5, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)

            VStack(spacing: 6) {
                Text(FridgeMailCopy.backHeadline(childName: item.childName, ageText: item.ageText, date: Date(), calendar: calendar))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if !item.note.isEmpty {
                    Text(item.note).font(.system(size: 13)).multilineTextAlignment(.center)
                }
                Text(FridgeMailCopy.signature(familyName: familyName)).font(.system(size: 13, design: .serif)).italic()
            }
            .foregroundStyle(FridgeMailCanvasView.ink)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FridgeMailCanvasView.frame.opacity(0.4), lineWidth: 1))
        }
    }
}

/// After a photo is picked: see it on the card, name the child, write the
/// note, add it to the queue. The print file is rendered and uploaded here
/// so the weekly run has nothing to do but hand a URL to the printer.
struct FridgeMailAddSheet: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore
    let image: PostcardPlatformImage
    @Environment(\.dismiss) private var dismiss

    @State private var childName = ""
    @State private var ageText = ""
    @State private var note = ""
    @State private var isSaving = false

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FridgeMailCanvasView(image: image, childName: childName, size: CGSize(width: 330, height: 220))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
                        .frame(maxWidth: .infinity)
                    if PostcardRendering.isSoftForPrint(image) {
                        Label("This photo is small and may print soft.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(theme.warning)
                    }
                    WidgetUI.header("On the back", theme: theme)
                    HStack(spacing: 8) {
                        FridgeMailField("Child's name", text: $childName, theme: theme)
                        FridgeMailField("Age", text: $ageText, theme: theme).frame(width: 80)
                    }
                    TextField("A note for the fridge (optional)", text: $note, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(2...4)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        .onChange(of: note) { value in
                            if value.count > FridgeMailCopy.noteMaxChars { note = String(value.prefix(FridgeMailCopy.noteMaxChars)) }
                        }
                    Text(FridgeMailCopy.backHeadline(childName: childName, ageText: ageText, date: Date(), calendar: context.calendar)
                         + "\n" + FridgeMailCopy.signature(familyName: store.plan?.familyName ?? ""))
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.primaryButton(isSaving ? "Adding…" : "Add to the queue", color: context.accent) { save() }
                        .disabled(isSaving)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("New card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let jpeg = try FridgeMailRendering.printJPEG(image: image, childName: childName.trimmingCharacters(in: .whitespaces))
                let url = try await context.host.uploadPrintImage(jpeg)
                let plan = try await FridgeMailAPI.enqueue(
                    context: context, imageURL: url,
                    childName: childName.trimmingCharacters(in: .whitespaces),
                    ageText: ageText.trimmingCharacters(in: .whitespaces),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                store.apply(plan)
                context.track("fridgemail_enqueued")
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add it", message: error.localizedDescription))
            }
        }
    }
}

/// Name, relation and a US address. The server checks the address with
/// USPS before it's saved, so a typo is caught here and not at the printer.
struct FridgeMailRecipientSheet: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relation = "Grandma"
    @State private var address = PostcardMailAddress()
    @State private var isSaving = false

    private static let relations = ["Grandma", "Grandpa", "Nana", "Papa", "Aunt", "Uncle", ""]

    var body: some View {
        let theme = context.theme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(Self.relations, id: \.self) { r in
                                Button(r.isEmpty ? "Just the name" : r) { relation = r }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(relation.isEmpty ? "Relation" : relation)
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 15)).foregroundStyle(theme.label)
                            .frame(width: 110, height: 38)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        }
                        FridgeMailField("Name", text: $name, theme: theme)
                    }
                    Text("Printed on the card as \"\(relation.isEmpty ? name : "\(relation) \(name)")\".")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.header("Address", theme: theme)
                    FridgeMailField("Street address", text: $address.line1, theme: theme)
                    FridgeMailField("Apt, suite (optional)", text: $address.line2, theme: theme)
                    HStack(spacing: 8) {
                        FridgeMailField("City", text: $address.city, theme: theme)
                        Menu {
                            ForEach(PostcardMailAddress.states, id: \.self) { code in Button(code) { address.state = code } }
                        } label: {
                            HStack(spacing: 4) {
                                Text(address.state.isEmpty ? "State" : address.state)
                                    .foregroundStyle(address.state.isEmpty ? theme.secondaryLabel : theme.label)
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                            }
                            .font(.system(size: 15))
                            .frame(width: 78, height: 38)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        }
                    }
                    FridgeMailField("ZIP", text: $address.zip, theme: theme, numeric: true)
                    Text("US addresses only for now. We check it with USPS before saving.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    WidgetUI.primaryButton(isSaving ? "Checking the address…" : "Add", color: context.accent) { save() }
                        .disabled(isSaving || !canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Add a grandparent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
        }
    }

    private var canSave: Bool {
        var a = address
        a.name = name
        return a.isComplete
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let plan = try await FridgeMailAPI.addRecipient(
                    context: context, name: name.trimmingCharacters(in: .whitespaces), relation: relation, address: address)
                store.apply(plan)
                context.track("fridgemail_recipient_added")
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't add them", message: error.localizedDescription))
            }
        }
    }
}

/// The plain text field the two sheets share.
struct FridgeMailField: View {
    let placeholder: String
    @Binding var text: String
    let theme: WidgetTheme
    var numeric = false

    init(_ placeholder: String, text: Binding<String>, theme: WidgetTheme, numeric: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.theme = theme
        self.numeric = numeric
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 15))
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
            #if os(iOS)
            .keyboardType(numeric ? .numbersAndPunctuation : .default)
            .textInputAutocapitalization(.words)
            #endif
    }
}

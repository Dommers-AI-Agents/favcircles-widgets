import SwiftUI
import CoreLocation
import FavWidgetsCore
#if os(iOS)
import UIKit
#endif

/// Return Window (Wes, 2026-11-20): snap the receipt at the register. The
/// store comes from where you are, the date from the clock, and the return
/// window counts down — with a nudge three days before it closes.
public struct ReturnWindowWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "returnwindow",
        title: "Return Window",
        subtitle: "Snap the receipt, we count the days",
        symbolName: "receipt.fill",
        accentHex: "#2F855A",
        category: .money,
        schemaVersion: ReceiptList.schemaVersion,
        shareBlurb: "Snap a receipt at the register and know exactly how long you have to return it."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(ReturnWindowCardView(context: context, state: context.state(ReceiptList.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(ReturnWindowFullView(context: context, state: context.state(ReceiptList.self)))
    }
}

@MainActor
enum ReturnWindowActions {
    static let notificationType = "return_window"
    static let reminderPrefix = "returnwindow-"

    /// Three days before and the last morning, for every open receipt.
    static func syncReminders(_ list: ReceiptList, calendar: Calendar) async {
        let now = Date()
        let items = list.receipts.flatMap { receipt in
            ReturnWindowPlan.reminderTimes(receipt, now: now, calendar: calendar).map {
                WidgetLocalReminders.Item(id: $0.id, at: $0.at, title: "🧾 Return window", body: $0.text, type: notificationType)
            }
        }
        await WidgetLocalReminders.replace(prefix: reminderPrefix, with: items)
    }

    static func resolve(_ receipt: Receipt, _ resolution: Receipt.Resolution, context: WidgetContext, state: WidgetStateController<ReceiptList>) {
        state.update { list in
            guard let i = list.receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
            list.receipts[i].resolve(resolution)
        }
        context.host.haptic(.success)
        context.track("receipt_\(resolution.rawValue)")
        Task { await syncReminders(state.model, calendar: context.calendar) }
    }

    /// The store you are standing in: your nearest saved place, else what
    /// Apple's geocoder calls this address.
    static func storeHere(context: WidgetContext) async -> (name: String, placeId: String?)? {
        guard let here = await context.host.currentLocation() else { return nil }
        let mine = (try? await context.host.fetchPlaces(WidgetPlaceQuery(sources: [.mine], near: here, radiusMeters: 300))) ?? []
        if let nearest = WiFiPlan.nearestPlace(mine, to: here, radius: 150) { return (nearest.name, nearest.id) }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: here.latitude, longitude: here.longitude))
        if let name = marks?.first?.name, !name.isEmpty, name.first?.isNumber == false { return (name, nil) }
        return nil
    }

    // MARK: Photos (this phone only)

    static func photoURL(_ id: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FavWidgets/receipts", isDirectory: true).appendingPathComponent("\(id).jpg")
    }

    static func savePhoto(_ jpeg: Data, id: String) {
        guard let url = photoURL(id) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
    }

    static func loadPhoto(_ id: String) -> PostcardPlatformImage? {
        #if os(iOS)
        guard let url = photoURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
        #else
        return nil
        #endif
    }

    static func deletePhoto(_ id: String) {
        if let url = photoURL(id) { try? FileManager.default.removeItem(at: url) }
    }
}

struct ReturnWindowCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<ReceiptList>
    @State private var adding = false

    var body: some View {
        let theme = context.theme
        let today = context.today
        let open = ReturnWindowPlan.open(state.model.receipts, calendar: context.calendar)
        WidgetCard(context: context, action: WidgetQuickAction("Snap", symbolName: "camera.fill") { adding = true }) {
            VStack(alignment: .leading, spacing: 3) {
                WidgetUI.summary(ReturnWindowPlan.summary(state.model.receipts, today: today, calendar: context.calendar), theme: theme)
                if let next = open.first, ReturnWindowPlan.isClosingSoon(next, today: today, calendar: context.calendar) {
                    Label(ReturnWindowPlan.closesText(next, calendar: context.calendar), systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.warning)
                }
            }
        }
        .task { await state.loadIfNeeded() }
        .sheet(isPresented: $adding) { ReceiptAddSheet(context: context, state: state) }
    }
}

struct ReturnWindowFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<ReceiptList>
    @State private var adding = false
    @State private var viewing: Receipt?
    @State private var showResolved = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        let today = context.today
        let open = ReturnWindowPlan.open(state.model.receipts, calendar: context.calendar)
        let resolved = ReturnWindowPlan.resolved(state.model.receipts)
        List {
            Section {
                Button { adding = true } label: { Label("Snap a receipt", systemImage: "camera.fill").foregroundStyle(context.accent) }
            }
            Section(open.isEmpty ? "" : "Open windows") {
                if open.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lost receipts, missed windows — over.").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text("Snap the receipt at the register. The store and date fill themselves in, and you get a nudge three days before the window closes.")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(open) { r in
                    row(r, today: today)
                        .swipeActions(edge: .trailing) {
                            Button("Returned") { ReturnWindowActions.resolve(r, .returned, context: context, state: state) }.tint(.green)
                            Button("Keeping it") { ReturnWindowActions.resolve(r, .kept, context: context, state: state) }.tint(.gray)
                        }
                }
            }
            if !resolved.isEmpty {
                Section {
                    DisclosureGroup("Done (\(resolved.count))", isExpanded: $showResolved) {
                        ForEach(resolved) { r in row(r, today: today) }
                    }
                }
            }
            Section {
                Text("Saved on your account; receipt photos stay on this phone.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await state.loadIfNeeded()
            await ReturnWindowActions.syncReminders(state.model, calendar: context.calendar)
        }
        .sheet(isPresented: $adding) { ReceiptAddSheet(context: context, state: state) }
        .sheet(item: $viewing) { r in ReceiptDetailSheet(context: context, state: state, receipt: r) }
    }

    private func row(_ r: Receipt, today: DayKey) -> some View {
        let soon = r.isOpen && ReturnWindowPlan.isClosingSoon(r, today: today, calendar: context.calendar)
        let closed = r.isOpen && ReturnWindowPlan.daysLeft(r, today: today, calendar: context.calendar) < 0
        return Button { viewing = r } label: {
            HStack(spacing: 12) {
                ReceiptThumb(id: r.id, hasPhoto: r.hasPhoto, accent: context.accent, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                    Text(r.isOpen
                         ? "\(ReturnWindowPlan.statusText(r, today: today, calendar: context.calendar)) · \(ReturnWindowPlan.closesText(r, calendar: context.calendar))"
                         : (r.resolution == .returned ? "Returned" : "Kept") + " · bought \(r.purchasedOn.date(calendar: context.calendar).formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 13, weight: soon ? .semibold : .regular))
                        .foregroundStyle(closed ? theme.danger : (soon ? theme.warning : theme.secondaryLabel)).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The receipt photo at thumbnail size, or the widget's symbol.
struct ReceiptThumb: View {
    let id: String
    let hasPhoto: Bool
    let accent: Color
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.15))
            #if os(iOS)
            if hasPhoto, let image = ReturnWindowActions.loadPhoto(id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "receipt.fill").foregroundStyle(accent)
            }
            #else
            Image(systemName: "receipt.fill").foregroundStyle(accent)
            #endif
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Snap first, then the store (filled from where you are), the window and
/// what it was.
struct ReceiptAddSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<ReceiptList>
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PostcardPlatformImage?
    @State private var showCamera = false
    @State private var store = ""
    @State private var placeId: String?
    @State private var item = ""
    @State private var windowDays = ReturnWindowPlan.defaultWindowDays
    @State private var purchased = Date()
    @State private var locating = true
    @State private var windowTouched = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        WidgetSheet(title: "New receipt", theme: theme, confirm: ("Save", !store.trimmingCharacters(in: .whitespaces).isEmpty, save)) {
            Form {
                Section {
                    #if os(iOS)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if PostcardCameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            Label(photo == nil ? "Snap the receipt" : "Retake", systemImage: "camera.fill")
                        }
                    }
                    #endif
                }
                Section("Store") {
                    HStack {
                        TextField("Store", text: $store)
                            .onChange(of: store) { value in
                                if !windowTouched { windowDays = state.model.windowDays(for: value) }
                            }
                        if locating { ProgressView().controlSize(.small) }
                    }
                    DatePicker("Bought", selection: $purchased, in: ...Date(), displayedComponents: .date)
                }
                Section("Return window") {
                    HStack(spacing: 8) {
                        ForEach(ReturnWindowPlan.windowChoices, id: \.self) { d in
                            Button { windowDays = d; windowTouched = true } label: {
                                Text("\(d) days").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(windowDays == d ? .white : theme.label)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Capsule().fill(windowDays == d ? context.accent : theme.tertiaryBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Closes \(DayKey(purchased, calendar: context.calendar).adding(days: windowDays, calendar: context.calendar).date(calendar: context.calendar).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                Section {
                    TextField("What did you buy? (optional)", text: $item)
                }
            }
            .task {
                // Camera first — "snap at the register" — while the store
                // resolves underneath. A cover presented on the sheet's very
                // first frame can be dropped by UIKit, hence the short delay.
                #if os(iOS)
                if PostcardCameraPicker.isAvailable, photo == nil {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if !Task.isCancelled { showCamera = true }
                }
                #endif
            }
            .task {
                if let here = await ReturnWindowActions.storeHere(context: context), store.isEmpty {
                    store = here.name; placeId = here.placeId
                    if !windowTouched { windowDays = state.model.windowDays(for: here.name) }
                }
                locating = false
            }
            #if os(iOS)
            .widgetCameraCover(isPresented: $showCamera) { PostcardCameraPicker(image: $photo).ignoresSafeArea() }
            #endif
        }
    }

    private func save() {
        let name = store.trimmingCharacters(in: .whitespaces)
        var receipt = Receipt(storeName: name, placeId: placeId, item: item.trimmingCharacters(in: .whitespaces),
                              purchasedOn: DayKey(purchased, calendar: context.calendar), windowDays: windowDays)
        #if os(iOS)
        if let photo, let jpeg = photo.jpegData(compressionQuality: 0.65) {
            ReturnWindowActions.savePhoto(jpeg, id: receipt.id)
            receipt.hasPhoto = true
        }
        #endif
        state.update { $0.add(receipt) }
        context.host.haptic(.success)
        context.track("receipt_saved", ["window": "\(windowDays)"])
        Task { await ReturnWindowActions.syncReminders(state.model, calendar: context.calendar) }
        dismiss()
    }
}

/// The photo big, the countdown, and Returned / Keeping it.
struct ReceiptDetailSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<ReceiptList>
    let receipt: Receipt
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var theme: WidgetTheme { context.theme }
    private var current: Receipt { state.model.receipts.first { $0.id == receipt.id } ?? receipt }

    var body: some View {
        let r = current
        let today = context.today
        WidgetSheet(title: r.storeName, theme: theme) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    #if os(iOS)
                    if r.hasPhoto, let image = ReturnWindowActions.loadPhoto(r.id) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    #endif
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                        Text("Bought \(r.purchasedOn.date(calendar: context.calendar).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())) · \(r.windowDays)-day window")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        if r.isOpen {
                            Text("\(ReturnWindowPlan.statusText(r, today: today, calendar: context.calendar)) · \(ReturnWindowPlan.closesText(r, calendar: context.calendar))")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ReturnWindowPlan.daysLeft(r, today: today, calendar: context.calendar) < 0 ? theme.danger
                                                 : (ReturnWindowPlan.isClosingSoon(r, today: today, calendar: context.calendar) ? theme.warning : context.accent))
                        } else {
                            Text(r.resolution == .returned ? "Returned" : "Kept").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    if r.isOpen {
                        WidgetUI.primaryButton("I returned it", color: context.accent) {
                            ReturnWindowActions.resolve(r, .returned, context: context, state: state); dismiss()
                        }
                        Button("I'm keeping it") { ReturnWindowActions.resolve(r, .kept, context: context, state: state); dismiss() }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).frame(maxWidth: .infinity)
                    } else {
                        Button("Reopen the window") {
                            state.update { list in
                                guard let i = list.receipts.firstIndex(where: { $0.id == r.id }) else { return }
                                list.receipts[i].resolution = nil; list.receipts[i].resolvedAt = nil; list.receipts[i].updatedAt = Date()
                            }
                            Task { await ReturnWindowActions.syncReminders(state.model, calendar: context.calendar) }
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent).frame(maxWidth: .infinity)
                    }
                    Button("Delete receipt", role: .destructive) { confirmDelete = true }
                        .font(.system(size: 14)).frame(maxWidth: .infinity).padding(.top, 8)
                }
                .padding(16)
            }
            .confirmationDialog("Delete this receipt and its photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    state.update { $0.receipts.removeAll { $0.id == r.id } }
                    ReturnWindowActions.deletePhoto(r.id)
                    Task { await ReturnWindowActions.syncReminders(state.model, calendar: context.calendar) }
                    dismiss()
                }
            }
        }
    }
}

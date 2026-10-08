import SwiftUI
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif
#if os(iOS)
import UIKit
#endif

/// Package Tracker (Wes, 2026-10-08): add a tracking number (paste, type or
/// scan the label), the carrier is detected, tap to open its tracking page.
/// No tracking API: nothing is fetched, so it's free and private.
public struct PackagesWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "packages",
        title: "Packages",
        subtitle: "Every tracking number in one place",
        symbolName: "shippingbox.fill",
        accentHex: "#B7791F",
        category: .money,
        schemaVersion: PackageList.schemaVersion,
        shareBlurb: "Keep every tracking number in one place and open each carrier's tracking in a tap."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(PackagesCardView(context: context, state: context.state(PackageList.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(PackagesFullView(context: context, state: context.state(PackageList.self)))
    }
}

@MainActor
enum PackageActions {
    static let notificationType = "package_expected"

    static func open(_ p: TrackedPackage, context: WidgetContext) {
        if let url = p.carrier.trackingURL(p.number) { context.host.openURL(url) }
        context.track("package_opened", ["carrier": p.carrier.rawValue])
    }

    /// A tracking number on the clipboard, if there is one (iOS shows its own paste banner).
    static func clipboardNumber() -> String? {
        #if os(iOS)
        guard UIPasteboard.general.hasStrings, let s = UIPasteboard.general.string,
              CarrierDetector.looksLikeTrackingNumber(s) else { return nil }
        return CarrierDetector.normalize(s)
        #else
        return nil
        #endif
    }

    /// "Your shoes arrive today" at 8 AM on the expected day.
    static func syncReminders(_ list: PackageList, calendar: Calendar) async {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("package-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        let today = DayKey(Date(), calendar: calendar)
        for p in list.inTransit {
            guard let day = p.expectedOn, day >= today,
                  let at = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day.date(calendar: calendar)), at > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "📦 \(p.title)"
            content.body = "Arrives today (\(p.carrier.name)). Tap to track it."
            content.sound = .default
            content.userInfo = ["type": notificationType]
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            try? await center.add(UNNotificationRequest(identifier: "package-\(p.id)", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        #endif
    }
}

struct PackagesCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<PackageList>
    @State private var adding = false

    var body: some View {
        let theme = context.theme
        let inTransit = state.model.inTransit
        let today = DayKey(Date(), calendar: context.calendar)
        WidgetCard(context: context, action: WidgetQuickAction("Add", symbolName: "plus") { adding = true }) {
            if let next = inTransit.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(inTransit.count == 1 ? "1 on the way" : "\(inTransit.count) on the way")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    Text([next.title, next.expectedText(today: today, calendar: context.calendar)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
            } else {
                WidgetUI.summary("Add a tracking number to keep an eye on it", theme: theme)
            }
        }
        .task { await state.loadIfNeeded() }
        .sheet(isPresented: $adding) { PackageAddSheet(context: context, state: state) }
    }
}

struct PackagesFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<PackageList>
    @State private var adding = false
    @State private var editing: TrackedPackage?
    @State private var showDelivered = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        let today = DayKey(Date(), calendar: context.calendar)
        List {
            Section {
                Button { adding = true } label: { Label("Add a tracking number", systemImage: "plus.circle.fill").foregroundStyle(context.accent) }
            }
            Section(state.model.inTransit.isEmpty ? "" : "On the way") {
                if state.model.inTransit.isEmpty {
                    Text("Nothing on the way. Paste, type or scan a tracking number.").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                }
                ForEach(state.model.inTransit) { p in
                    row(p, today: today)
                        .swipeActions(edge: .trailing) {
                            Button("Delivered") { setDelivered(p, true) }.tint(.green)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { editing = p }.tint(.gray)
                        }
                }
            }
            if !state.model.delivered.isEmpty {
                Section {
                    DisclosureGroup("Delivered (\(state.model.delivered.count))", isExpanded: $showDelivered) {
                        ForEach(state.model.delivered) { p in
                            row(p, today: today)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) { delete(p) }
                                    Button("Not yet") { setDelivered(p, false) }
                                }
                        }
                    }
                }
            }
            Section {
                Text("Tap a package to open the carrier's tracking page. Swipe for Delivered or Edit. Nothing is looked up for you, so your numbers stay private.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .task {
            await state.loadIfNeeded()
            await PackageActions.syncReminders(state.model, calendar: context.calendar)
        }
        .onChange(of: state.model) { list in Task { await PackageActions.syncReminders(list, calendar: context.calendar) } }
        .sheet(isPresented: $adding) { PackageAddSheet(context: context, state: state) }
        .sheet(item: $editing) { p in PackageAddSheet(context: context, state: state, editing: p) }
    }

    private func row(_ p: TrackedPackage, today: DayKey) -> some View {
        Button { PackageActions.open(p, context: context) } label: {
            HStack(spacing: 12) {
                Text(p.carrier.name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 58, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: p.carrier.colorHex)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label)
                    Text([p.shortNumber, p.deliveredAt == nil ? p.expectedText(today: today, calendar: context.calendar) : "Delivered"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(theme.secondaryLabel)
            }
        }
        .buttonStyle(.plain)
    }

    private func setDelivered(_ p: TrackedPackage, _ delivered: Bool) {
        state.update { list in
            guard let i = list.packages.firstIndex(where: { $0.id == p.id }) else { return }
            list.packages[i].deliveredAt = delivered ? Date() : nil
            list.packages[i].updatedAt = Date()
        }
        context.host.haptic(.success)
    }

    private func delete(_ p: TrackedPackage) {
        state.update { $0.packages.removeAll { $0.id == p.id } }
    }
}

/// Add (paste / type / scan) or edit one package.
struct PackageAddSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<PackageList>
    var editing: TrackedPackage?
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var nickname = ""
    @State private var carrier: Carrier = .other
    @State private var carrierTouched = false
    @State private var hasDate = false
    @State private var expected = Date()
    @State private var scanning = false
    @State private var duplicate = false

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: editing == nil ? "Add package" : "Edit package", theme: theme,
                    confirm: ("Save", CarrierDetector.normalize(number).count >= 8, save)) {
            Form {
                Section {
                    TextField("Tracking number", text: $number)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .disabled(editing != nil)
                        .onChange(of: number) { value in
                            if !carrierTouched { carrier = CarrierDetector.detect(value) }
                            duplicate = false
                        }
                    if editing == nil {
                        HStack {
                            if let clip = PackageActions.clipboardNumber(), clip != CarrierDetector.normalize(number) {
                                Button("Paste \(clip.count > 12 ? "…" + clip.suffix(8) : Substring(clip))") { number = clip }
                            }
                            Spacer()
                            if PackageScanner.isAvailable {
                                Button { scanning = true } label: { Label("Scan label", systemImage: "barcode.viewfinder") }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    if duplicate { Text("That number is already in your list.").font(.system(size: 12)).foregroundStyle(theme.danger) }
                }
                Section {
                    TextField("What is it? (optional)", text: $nickname)
                    Picker("Carrier", selection: Binding(get: { carrier }, set: { carrier = $0; carrierTouched = true })) {
                        ForEach(Carrier.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Toggle("Expected delivery date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Arrives", selection: $expected, displayedComponents: .date)
                    }
                } footer: { Text(hasDate ? "We'll remind you that morning." : "") }
            }
        }
        .onAppear {
            if let e = editing {
                number = e.number; nickname = e.nickname; carrier = e.carrier; carrierTouched = true
                if let d = e.expectedOn { hasDate = true; expected = d.date(calendar: context.calendar) }
            } else if let clip = PackageActions.clipboardNumber() {
                number = clip
            }
        }
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            PackageScanner { found in number = found; scanning = false }.ignoresSafeArea()
        }
        #endif
    }

    private func save() {
        let day = hasDate ? DayKey(expected, calendar: context.calendar) : nil
        if let e = editing {
            state.update { list in
                guard let i = list.packages.firstIndex(where: { $0.id == e.id }) else { return }
                list.packages[i].nickname = nickname.trimmingCharacters(in: .whitespaces)
                list.packages[i].carrier = carrier
                list.packages[i].expectedOn = day
                list.packages[i].updatedAt = Date()
            }
            dismiss(); return
        }
        var added = false
        state.update { list in
            added = list.add(TrackedPackage(number: number, carrier: carrier, nickname: nickname.trimmingCharacters(in: .whitespaces), expectedOn: day))
        }
        if added {
            context.host.haptic(.success)
            context.track("package_added", ["carrier": carrier.rawValue])
            dismiss()
        } else {
            duplicate = true
        }
    }
}

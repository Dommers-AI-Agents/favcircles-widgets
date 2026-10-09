import SwiftUI
import FavWidgetsCore
#if os(iOS)
import AddressBook
import Contacts
import ContactsUI
import UIKit
#endif

/// New Contacts (Wes, 2026-10-09): the last 50 people added to this phone's
/// contacts, newest first, with Call / Text / Email and the contact card one
/// tap away. Everything is read on the phone at the moment the widget shows;
/// nothing is uploaded, stored or logged (analytics carry counts only).
public struct NewContactsWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "newcontacts",
        title: "New Contacts",
        subtitle: "The last 50 people you added to your phone",
        symbolName: "person.crop.circle.badge.plus",
        accentHex: "#2B6CB0",
        category: .social,
        shareBlurb: "See the last 50 people you added to your phone, newest first — and call or text them in a tap."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(NewContactsCardView(context: context, model: NewContactsModel.shared))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(NewContactsFullView(context: context, model: NewContactsModel.shared))
    }
}

// MARK: - Model

/// Whether we may read contacts, and what was read. Shared by the card and
/// the full view so the list is read once per appearance, not twice.
@MainActor
final class NewContactsModel: ObservableObject {
    static let shared = NewContactsModel()

    enum Access: Equatable { case notAsked, denied, limited, full, unavailable }

    @Published private(set) var access: Access = .notAsked
    @Published private(set) var contacts: [RecentContact] = []
    @Published private(set) var loading = false
    private var lastRead: Date?

    func refreshAccess() {
        #if os(iOS)
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined: access = .notAsked
        case .denied, .restricted: access = .denied
        case .authorized: access = .full
        default:
            // iOS 18's "only some contacts" access
            if #available(iOS 18.0, *), status == .limited { access = .limited } else { access = .full }
        }
        #else
        access = .unavailable
        #endif
    }

    /// Asks once (the system prompt), then reads.
    func requestAccess() async {
        #if os(iOS)
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        refreshAccess()
        await load(force: true)
        #endif
    }

    /// Reads unless it read in the last few seconds (card + full view appearing together).
    func load(force: Bool = false) async {
        refreshAccess()
        guard access == .full || access == .limited else { contacts = []; return }
        if !force, let lastRead, Date().timeIntervalSince(lastRead) < 5 { return }
        loading = true
        contacts = await Task.detached(priority: .userInitiated) { NewContactsReader.latest() }.value
        lastRead = Date()
        loading = false
    }
}

/// Reads the phone's contacts with their "first saved" dates.
///
/// AddressBook, not Contacts, on purpose: only AddressBook exposes when a
/// contact was created (`kABPersonCreationDateProperty`). It's deprecated
/// but still works on iOS 26 (checked on the simulator 2026-10-09: sample
/// contacts carry their seed date, a new contact carries today). Uses the
/// same Contacts permission. Runs off the main thread; one address book per
/// read, used only on that thread.
enum NewContactsReader {
    static func latest(limit: Int = RecentContacts.limit) -> [RecentContact] {
        #if os(iOS)
        guard let book = ABAddressBookCreateWithOptions(nil, nil)?.takeRetainedValue(),
              let people = ABAddressBookCopyArrayOfAllPeople(book)?.takeRetainedValue() as? [ABRecord] else { return [] }
        // Dates for everyone, details only for the newest
        let dated: [(ABRecord, Date)] = people.compactMap { person in
            guard let created = ABRecordCopyValue(person, kABPersonCreationDateProperty)?.takeRetainedValue() as? Date else { return nil }
            return (person, created)
        }
        let newest = dated.sorted { $0.1 > $1.1 }.prefix(limit * 2) // a little extra so name ties sort fairly
        let contacts = newest.map { person, created in
            let first = string(person, kABPersonFirstNameProperty)
            let last = string(person, kABPersonLastNameProperty)
            let org = string(person, kABPersonOrganizationProperty)
            let phone = firstValue(person, kABPersonPhoneProperty)
            let email = firstValue(person, kABPersonEmailProperty)
            let thumb = ABPersonHasImageData(person)
                ? ABPersonCopyImageDataWithFormat(person, kABPersonImageFormatThumbnail)?.takeRetainedValue() as Data?
                : nil
            return RecentContact(
                id: "\(ABRecordGetRecordID(person))",
                name: RecentContacts.displayName(first: first, last: last, organization: org, phone: phone, email: email),
                organization: (first ?? last) == nil ? nil : org,
                phone: phone, email: email, addedAt: created, thumbnail: thumb)
        }
        return RecentContacts.latest(contacts, limit: limit)
        #else
        return []
        #endif
    }

    #if os(iOS)
    private static func string(_ person: ABRecord, _ property: ABPropertyID) -> String? {
        (ABRecordCopyValue(person, property)?.takeRetainedValue() as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func firstValue(_ person: ABRecord, _ property: ABPropertyID) -> String? {
        guard let multi = ABRecordCopyValue(person, property)?.takeRetainedValue(),
              ABMultiValueGetCount(multi as ABMultiValue) > 0 else { return nil }
        return ABMultiValueCopyValueAtIndex(multi as ABMultiValue, 0)?.takeRetainedValue() as? String
    }
    #endif
}

// MARK: - Card

struct NewContactsCardView: View {
    let context: WidgetContext
    @ObservedObject var model: NewContactsModel

    var body: some View {
        WidgetCard(context: context, action: model.access == .notAsked
                   ? WidgetQuickAction("Show them", symbolName: "person.2.fill") { Task { await model.requestAccess() } }
                   : nil) {
            WidgetUI.summary(summary, theme: context.theme)
        }
        .task { await model.load() }
    }

    private var summary: String {
        switch model.access {
        case .notAsked: return "See the last 50 people you added to your phone"
        case .denied: return "Turn on Contacts for FavCircles in Settings to see them"
        case .unavailable: return "Available on iPhone"
        case .full, .limited: return RecentContacts.cardSummary(model.contacts, calendar: context.calendar)
        }
    }
}

// MARK: - Full view

struct NewContactsFullView: View {
    let context: WidgetContext
    @ObservedObject var model: NewContactsModel
    @State private var opening: RecentContact?
    @Environment(\.scenePhase) private var scenePhase

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch model.access {
                case .notAsked: ask
                case .denied: denied
                case .unavailable: Text("Available on iPhone").foregroundStyle(theme.secondaryLabel)
                case .full, .limited: list
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .refreshable { await model.load(force: true) }
        .task {
            await model.load(force: true)
            context.track("newcontacts_opened", ["count": "\(model.contacts.count)"])
        }
        // Back from Settings or the Contacts app: read again
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.load(force: true) } }
        }
        #if os(iOS)
        .sheet(item: $opening) { contact in
            ContactCardSheet(contact: contact).ignoresSafeArea()
        }
        #endif
    }

    private var ask: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 46)).foregroundStyle(context.accent)
            Text("See the last 50 people you added to your phone, newest first.")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label).multilineTextAlignment(.center)
            privacyNote
            WidgetUI.primaryButton("Show my new contacts", color: context.accent) {
                Task { await model.requestAccess() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var denied: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.xmark").font(.system(size: 46)).foregroundStyle(theme.secondaryLabel)
            Text("FavCircles can't see your contacts.")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
            Text("Turn on Contacts for FavCircles in Settings, then come back.")
                .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
            WidgetUI.primaryButton("Open Settings", color: context.accent) { openSettings() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var privacyNote: some View {
        Label("Read on your phone only. Never uploaded or saved.", systemImage: "lock.fill")
            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
    }

    @ViewBuilder private var list: some View {
        if model.access == .limited {
            Button { openSettings() } label: {
                Text("You've shared only some contacts with FavCircles. Change that in Settings ›")
                    .font(.system(size: 13)).foregroundStyle(context.accent).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        if model.contacts.isEmpty {
            Text(model.loading ? "Reading your contacts…" : "No contacts yet.")
                .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                .frame(maxWidth: .infinity).padding(.top, 30)
        } else {
            let imported = RecentContacts.importedMinutes(model.contacts)
            ForEach(RecentContacts.sections(model.contacts, calendar: context.calendar), id: \.title) { section in
                WidgetUI.header(section.title, theme: theme)
                VStack(spacing: 0) {
                    ForEach(section.contacts) { contact in
                        row(contact, imported: RecentContacts.isImported(contact, in: imported))
                        if contact.id != section.contacts.last?.id { Divider().padding(.leading, 60) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).fill(theme.secondaryBackground))
            }
            privacyNote.frame(maxWidth: .infinity).padding(.top, 4)
        }
    }

    private func row(_ contact: RecentContact, imported: Bool) -> some View {
        HStack(spacing: 12) {
            Button { open(contact) } label: {
                HStack(spacing: 12) {
                    avatar(contact)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                        Text([imported ? "Imported together" : RecentContacts.addedText(contact.addedAt, calendar: context.calendar),
                              contact.organization ?? contact.phone ?? contact.email].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the contact card")

            if let phone = contact.phone {
                actionButton("phone.fill", label: "Call \(contact.name)") { openLink("tel:\(RecentContacts.dialable(phone))", "call") }
                actionButton("message.fill", label: "Text \(contact.name)") { openLink("sms:\(RecentContacts.dialable(phone))", "text") }
            } else if let email = contact.email {
                actionButton("envelope.fill", label: "Email \(contact.name)") { openLink("mailto:\(email)", "email") }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func avatar(_ contact: RecentContact) -> some View {
        Group {
            #if os(iOS)
            if let data = contact.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { initials(contact) }
            #else
            initials(contact)
            #endif
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func initials(_ contact: RecentContact) -> some View {
        ZStack {
            Circle().fill(context.accent.opacity(0.18))
            Text(contact.initials).font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
        }
    }

    private func actionButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(context.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func open(_ contact: RecentContact) {
        context.track("newcontacts_card_opened")
        opening = contact
    }

    private func openLink(_ string: String, _ kind: String) {
        guard let url = URL(string: string) else { return }
        context.track("newcontacts_action", ["action": kind])
        context.host.openURL(url)
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { context.host.openURL(url) }
        #endif
    }
}

#if os(iOS)
/// The system contact card for a row. AddressBook ids don't map to Contacts
/// ids, so the contact is found by name and, when there's a phone, matched on
/// its digits; if nothing matches, the card shows what we know.
private struct ContactCardSheet: UIViewControllerRepresentable {
    let contact: RecentContact

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        let candidates = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: contact.name), keysToFetch: keys)) ?? []
        let digits = contact.phone.map(RecentContacts.dialable)
        let match = candidates.first { candidate in
            guard let digits, !digits.isEmpty else { return true }
            return candidate.phoneNumbers.contains { RecentContacts.dialable($0.value.stringValue).hasSuffix(String(digits.suffix(7))) }
        } ?? candidates.first
        let controller: CNContactViewController
        if let match {
            controller = CNContactViewController(for: match)
        } else {
            let fallback = CNMutableContact()
            fallback.givenName = contact.name
            if let phone = contact.phone { fallback.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))] }
            controller = CNContactViewController(forUnknownContact: fallback)
        }
        controller.contactStore = store
        controller.allowsEditing = true
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak controller] _ in
            controller?.dismiss(animated: true)
        })
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
#endif

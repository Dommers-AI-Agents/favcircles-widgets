import Foundation

/// Return Window (Wes, 2026-11-20): snap the receipt at the register; the
/// store comes from where you are, the date from the clock, and a countdown
/// to the last day you can return it starts. One document; returned and
/// kept receipts stay (never pruned). Photos stay on the phone.
public struct ReceiptList: WidgetModel {
    public static let schemaVersion = 1
    public var receipts: [Receipt]
    /// The window last used at each store, so the second visit is one tap.
    public var windowByStore: [String: Int]
    public init(receipts: [Receipt] = [], windowByStore: [String: Int] = [:]) {
        self.receipts = receipts; self.windowByStore = windowByStore
    }
    public static let empty = ReceiptList()

    /// Two phones: union by id; the same receipt keeps the later edit.
    public static func merge(local: ReceiptList, remote: ReceiptList) -> ReceiptList {
        var byId = Dictionary(remote.receipts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in local.receipts where (byId[r.id]?.updatedAt ?? .distantPast) <= r.updatedAt { byId[r.id] = r }
        return ReceiptList(receipts: byId.values.sorted { $0.createdAt < $1.createdAt },
                           windowByStore: remote.windowByStore.merging(local.windowByStore) { _, l in l })
    }

    /// Window for a store: what was used there last, else the usual 30.
    public func windowDays(for store: String) -> Int {
        windowByStore[ReturnWindowPlan.storeKey(store)] ?? ReturnWindowPlan.defaultWindowDays
    }

    public mutating func add(_ receipt: Receipt) {
        receipts.append(receipt)
        windowByStore[ReturnWindowPlan.storeKey(receipt.storeName)] = receipt.windowDays
    }
}

public struct Receipt: Codable, Equatable, Identifiable, Sendable {
    public enum Resolution: String, Codable, Sendable { case returned, kept }

    public var id: String
    public var storeName: String
    public var placeId: String?
    /// What you bought, in your words ("running shoes"); may be empty.
    public var item: String
    public var purchasedOn: DayKey
    public var windowDays: Int
    public var hasPhoto: Bool
    public var resolution: Resolution?
    public var resolvedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, storeName: String, placeId: String? = nil, item: String = "",
                purchasedOn: DayKey, windowDays: Int, hasPhoto: Bool = false, createdAt: Date = Date()) {
        self.id = id; self.storeName = storeName; self.placeId = placeId; self.item = item
        self.purchasedOn = purchasedOn; self.windowDays = windowDays; self.hasPhoto = hasPhoto
        self.createdAt = createdAt; self.updatedAt = createdAt
    }

    /// The last day a return is accepted (purchase day + window).
    public func closesOn(calendar: Calendar = .current) -> DayKey {
        purchasedOn.adding(days: windowDays, calendar: calendar)
    }

    public var isOpen: Bool { resolution == nil }

    /// "Running shoes at REI" / "REI"
    public var title: String { item.isEmpty ? storeName : "\(item) at \(storeName)" }

    public mutating func resolve(_ resolution: Resolution, at date: Date = Date()) {
        self.resolution = resolution
        resolvedAt = date
        updatedAt = date
    }
}

public enum ReturnWindowPlan {
    public static let defaultWindowDays = 30
    public static let windowChoices = [14, 30, 60, 90]

    /// Store names compare case- and space-insensitively ("REI " == "rei").
    public static func storeKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Days until the window closes; 0 on the last day, negative after.
    public static func daysLeft(_ receipt: Receipt, today: DayKey, calendar: Calendar = .current) -> Int {
        let closes = receipt.closesOn(calendar: calendar)
        return calendar.dateComponents([.day], from: today.date(calendar: calendar), to: closes.date(calendar: calendar)).day ?? 0
    }

    /// "Last day today" / "Tomorrow is the last day" / "12 days left" / "Closed 3 days ago"
    public static func statusText(_ receipt: Receipt, today: DayKey, calendar: Calendar = .current) -> String {
        let left = daysLeft(receipt, today: today, calendar: calendar)
        switch left {
        case 0: return "Last day today"
        case 1: return "Tomorrow is the last day"
        case 2...: return "\(left) days left"
        case -1: return "Closed yesterday"
        default: return "Closed \(-left) days ago"
        }
    }

    /// "Closes Dec 19" — the date on the row.
    public static func closesText(_ receipt: Receipt, calendar: Calendar = .current) -> String {
        "Closes " + receipt.closesOn(calendar: calendar).date(calendar: calendar).formatted(.dateTime.month(.abbreviated).day())
    }

    /// Soonest-closing first; already-closed open receipts first of all.
    public static func open(_ receipts: [Receipt], calendar: Calendar = .current) -> [Receipt] {
        receipts.filter(\.isOpen).sorted {
            let a = $0.closesOn(calendar: calendar), b = $1.closesOn(calendar: calendar)
            return a != b ? a < b : $0.createdAt > $1.createdAt
        }
    }

    /// Most recently resolved first.
    public static func resolved(_ receipts: [Receipt]) -> [Receipt] {
        receipts.filter { !$0.isOpen }.sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
    }

    /// Whether a window is in its last few days (row turns amber).
    public static func isClosingSoon(_ receipt: Receipt, today: DayKey, calendar: Calendar = .current) -> Bool {
        (0...3).contains(daysLeft(receipt, today: today, calendar: calendar))
    }

    /// "2 open · Running shoes at REI, 5 days left"
    public static func summary(_ receipts: [Receipt], today: DayKey, calendar: Calendar = .current) -> String {
        let open = open(receipts, calendar: calendar).filter { daysLeft($0, today: today, calendar: calendar) >= 0 }
        guard let next = open.first else { return "Snap a receipt at the register and we'll count down the return window" }
        let count = open.count == 1 ? "1 open" : "\(open.count) open"
        return "\(count) · \(next.title), \(statusText(next, today: today, calendar: calendar).lowercased())"
    }

    /// Three days before at 9 AM, and the last morning — only the ones still
    /// ahead.
    public static func reminderTimes(_ receipt: Receipt, now: Date, calendar: Calendar = .current) -> [(id: String, at: Date, text: String)] {
        guard receipt.isOpen else { return [] }
        let closes = receipt.closesOn(calendar: calendar)
        var out: [(String, Date, String)] = []
        if let warn = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: closes.adding(days: -3, calendar: calendar).date(calendar: calendar)), warn > now {
            out.append(("returnwindow-\(receipt.id)-warn", warn, "3 days left to return \(receipt.title)"))
        }
        if let last = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: closes.date(calendar: calendar)), last > now {
            out.append(("returnwindow-\(receipt.id)-last", last, "Today is the last day to return \(receipt.title)"))
        }
        return out
    }
}

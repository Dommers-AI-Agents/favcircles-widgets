import Foundation

/// Package Tracker (Wes, 2026-10-08): numbers you're waiting on, the carrier
/// detected from each, tap to open its tracking page. One document; delivered
/// ones are kept (never pruned).
public struct PackageList: WidgetModel {
    public static let schemaVersion = 1
    public var packages: [TrackedPackage]
    public init(packages: [TrackedPackage] = []) { self.packages = packages }
    public static let empty = PackageList()

    public var inTransit: [TrackedPackage] {
        packages.filter { $0.deliveredAt == nil }.sorted {
            ($0.expectedOn?.rawValue ?? "9999", $0.addedAt) < ($1.expectedOn?.rawValue ?? "9999", $1.addedAt)
        }
    }
    public var delivered: [TrackedPackage] {
        packages.filter { $0.deliveredAt != nil }.sorted { ($0.deliveredAt ?? .distantPast) > ($1.deliveredAt ?? .distantPast) }
    }

    /// Adds a number; the same number twice keeps the first (returns false).
    @discardableResult
    public mutating func add(_ package: TrackedPackage) -> Bool {
        guard !packages.contains(where: { $0.number == package.number }) else { return false }
        packages.append(package)
        return true
    }

    /// Two phones: union by id; the same package keeps the later change.
    public static func merge(local: PackageList, remote: PackageList) -> PackageList {
        var byId = Dictionary(remote.packages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in local.packages {
            if let r = byId[p.id], r.updatedAt > p.updatedAt { continue }
            byId[p.id] = p
        }
        return PackageList(packages: byId.values.sorted { $0.addedAt < $1.addedAt })
    }
}

public struct TrackedPackage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// Normalized (no spaces/dashes, uppercased)
    public var number: String
    public var carrier: Carrier
    public var nickname: String
    public var addedAt: Date
    public var expectedOn: DayKey?
    public var deliveredAt: Date?
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, number: String, carrier: Carrier? = nil, nickname: String = "",
                addedAt: Date = Date(), expectedOn: DayKey? = nil, deliveredAt: Date? = nil) {
        let n = CarrierDetector.normalize(number)
        self.id = id; self.number = n; self.carrier = carrier ?? CarrierDetector.detect(n); self.nickname = nickname
        self.addedAt = addedAt; self.expectedOn = expectedOn; self.deliveredAt = deliveredAt; self.updatedAt = addedAt
    }

    public var title: String { nickname.isEmpty ? "\(carrier.name) package" : nickname }

    /// "…7428490" — the end people recognise
    public var shortNumber: String { number.count > 10 ? "…" + number.suffix(8) : number }

    /// "Arrives today" / "Arrives Fri" / "Expected Oct 3 (late)"
    public func expectedText(today: DayKey, calendar: Calendar = .current) -> String? {
        guard let e = expectedOn else { return nil }
        if e == today { return "Arrives today" }
        if e == today.adding(days: 1, calendar: calendar) { return "Arrives tomorrow" }
        let date = e.date(calendar: calendar)
        if e < today { return "Expected \(date.formatted(.dateTime.month(.abbreviated).day())) (late)" }
        return "Arrives \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }
}

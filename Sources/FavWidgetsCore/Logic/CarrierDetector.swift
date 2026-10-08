import Foundation

/// Which carrier a tracking number belongs to, and its tracking page
/// (Wes, 2026-10-08: no tracking API — open the carrier's own page).
public enum Carrier: String, Codable, CaseIterable, Sendable {
    case ups, usps, fedex, amazon, dhl, ontrac, other

    public var name: String {
        switch self {
        case .ups: return "UPS"
        case .usps: return "USPS"
        case .fedex: return "FedEx"
        case .amazon: return "Amazon"
        case .dhl: return "DHL"
        case .ontrac: return "OnTrac"
        case .other: return "Other"
        }
    }

    /// Brand-ish colour for the row's badge
    public var colorHex: String {
        switch self {
        case .ups: return "#5C3D2E"
        case .usps: return "#004B87"
        case .fedex: return "#4D148C"
        case .amazon: return "#FF9900"
        case .dhl: return "#D40511"
        case .ontrac: return "#00A3E0"
        case .other: return "#718096"
        }
    }

    public func trackingURL(_ number: String) -> URL? {
        let n = number.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? number
        switch self {
        case .ups: return URL(string: "https://www.ups.com/track?tracknum=\(n)")
        case .usps: return URL(string: "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(n)")
        case .fedex: return URL(string: "https://www.fedex.com/fedextrack/?trknbr=\(n)")
        case .amazon: return URL(string: "https://www.amazon.com/progress-tracker/package?trackingId=\(n)")
        case .dhl: return URL(string: "https://www.dhl.com/us-en/home/tracking/tracking-express.html?tracking-id=\(n)")
        case .ontrac: return URL(string: "https://www.ontrac.com/tracking/?number=\(n)")
        case .other: return URL(string: "https://www.google.com/search?q=\(n)+tracking")
        }
    }
}

public enum CarrierDetector {
    /// Uppercased, spaces and dashes removed.
    public static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Looks like a tracking number at all (for "paste from clipboard").
    public static func looksLikeTrackingNumber(_ raw: String) -> Bool {
        let n = normalize(raw)
        guard (10...34).contains(n.count), n.contains(where: \.isNumber) else { return false }
        return detect(n) != .other || n.allSatisfy(\.isNumber)
    }

    public static func detect(_ raw: String) -> Carrier {
        let n = normalize(raw)
        func matches(_ pattern: String) -> Bool { n.range(of: "^" + pattern + "$", options: .regularExpression) != nil }
        let digits = n.allSatisfy(\.isNumber)

        if matches("1Z[0-9A-Z]{16}") || matches("T[0-9]{10}") || matches("K[0-9]{10}") { return .ups }
        if matches("TBA[0-9]{9,12}") || matches("TB[A-Z][0-9]{9,12}") { return .amazon }
        if matches("[A-Z]{2}[0-9]{9}US") { return .usps }
        if matches("JJD[0-9]{15,22}") || matches("JD[0-9]{16,18}") { return .dhl }
        if matches("[CD][0-9]{14}") { return .ontrac }
        if digits {
            // FedEx Ground 96… 22-digit, before USPS's 92–95
            if n.count == 22 && n.hasPrefix("96") { return .fedex }
            // USPS: 20/22/26 digits starting 92–95 (9400…, 9205…), or 420+ZIP routing prefixes
            if [20, 22, 26].contains(n.count), let second = n.dropFirst().first, n.hasPrefix("9"), "2345".contains(second) { return .usps }
            if n.hasPrefix("420") && (n.count == 30 || n.count == 34) { return .usps }
            // FedEx Ground 96… 22-digit, Express 12, Ground 15, SmartPost 20/22
            if n.count == 12 || n.count == 15 { return .fedex }
            if n.count == 20 { return .fedex }
            if n.count == 10 { return .dhl }
            if n.count == 18 { return .ups } // UPS Mail Innovations
        }
        return .other
    }
}

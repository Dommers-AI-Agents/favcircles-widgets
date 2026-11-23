import Foundation

/// "Scan a label" (Wes, 2026-11-23): photos of prescription labels are read
/// by AI on the server (`POST /api/widgets/meds/scan`) into DRAFTS. Nothing
/// is saved until the person has checked every medicine and confirmed; the
/// photos aren't kept. Schedules come from the label's stated frequency
/// (mapped on the server), never a guess: an unclear label comes back with
/// no times and `unsure`, so it can't be added until a time is set.
public struct MedLabelReading: Decodable, Equatable, Sendable {
    public var medications: [MedLabelDraft]
    public var notes: String?
    public var truncated: Bool

    public init(medications: [MedLabelDraft], notes: String? = nil, truncated: Bool = false) {
        self.medications = medications; self.notes = notes; self.truncated = truncated
    }

    /// The endpoint's reply: `{ success, kind, draft: { medications, notes }, truncated }`.
    public struct Response: Decodable, Sendable {
        struct Draft: Decodable { let medications: [MedLabelDraft]; let notes: String? }
        let draft: Draft
        let truncated: Bool?
        public var reading: MedLabelReading {
            MedLabelReading(medications: draft.medications, notes: draft.notes, truncated: truncated ?? false)
        }
    }
}

public struct MedLabelDraft: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var strength: String?
    public var amount: String?
    /// The directions as printed, shown beside the draft so it can be compared.
    public var directions: String?
    public var note: String?
    public var frequency: String
    /// Minutes after midnight
    public var times: [Int]
    /// 1 = Sunday … 7 = Saturday; empty = every day
    public var days: [Int]
    public var asNeeded: Bool
    public var unsure: Bool
    /// Why the schedule needs a look ("Suggested times…"), or nil.
    public var why: String?

    private enum CodingKeys: String, CodingKey {
        case name, strength, amount, directions, note, frequency, times, days, asNeeded, unsure, why
    }

    public init(id: String = UUID().uuidString, name: String, strength: String? = nil, amount: String? = nil,
                directions: String? = nil, note: String? = nil, frequency: String = "other", times: [Int] = [],
                days: [Int] = [], asNeeded: Bool = false, unsure: Bool = false, why: String? = nil) {
        self.id = id; self.name = name; self.strength = strength; self.amount = amount; self.directions = directions
        self.note = note; self.frequency = frequency; self.times = times; self.days = days
        self.asNeeded = asNeeded; self.unsure = unsure; self.why = why
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        strength = try c.decodeIfPresent(String.self, forKey: .strength)
        amount = try c.decodeIfPresent(String.self, forKey: .amount)
        directions = try c.decodeIfPresent(String.self, forKey: .directions)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency) ?? "other"
        times = (try c.decodeIfPresent([Int].self, forKey: .times) ?? []).filter { (0..<1440).contains($0) }
        days = (try c.decodeIfPresent([Int].self, forKey: .days) ?? []).filter { (1...7).contains($0) }
        asNeeded = try c.decodeIfPresent(Bool.self, forKey: .asNeeded) ?? false
        unsure = try c.decodeIfPresent(Bool.self, forKey: .unsure) ?? false
        why = try c.decodeIfPresent(String.self, forKey: .why)
    }

    /// "500 mg · 1 tablet"
    public var dose: String {
        [strength, amount].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The medication this draft would add (the person edits it before adding).
    public func med() -> Med {
        Med(name: name, dose: dose, times: times, days: days, note: note ?? "", active: true)
    }

    /// Ticked to add on first look: a reminder schedule was read and it isn't "as needed".
    public var includedByDefault: Bool { !asNeeded && !times.isEmpty }
}

public enum MedLabelScan {
    /// Photos per scan (the server's cap).
    public static let maxPhotos = 4
    /// Long edge the phone sends at; the server reads at 2,000 px.
    public static let uploadLongEdge: Double = 2000

    /// A medicine already in the list with the same name (refill bottle), so
    /// the review says so instead of adding a second set of reminders.
    public static func existing(_ draft: MedLabelDraft, in meds: [Med]) -> Med? {
        let key = normalized(draft.name)
        return meds.first { normalized($0.name) == key }
    }

    /// A draft can be added once it has a name and at least one time.
    public static func canAdd(_ med: Med) -> Bool {
        !med.name.trimmingCharacters(in: .whitespaces).isEmpty && !med.times.isEmpty
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The accuracy warning, word for word, everywhere it shows (review sheet,
/// widget footer). Mirrors Terms of Service §8 "Health and Medication Features".
public enum MedSafetyCopy {
    public static let scanWarningTitle = "Check everything before you add it"
    public static let scanWarning = "AI read these labels and can make mistakes. Compare each medicine, dose, time and day with your prescription label. You're responsible for the accuracy of your reminders. If anything is unclear, ask your pharmacist or doctor."
    public static let acknowledgement = "I've checked each medicine, dose and time against the label"
    public static let photoPrivacy = "Your photos are sent to our AI provider to be read, then discarded. Only what you add is saved, privately to you."
    public static let footer = "Reminders are a convenience, not medical advice. You're responsible for making sure every medicine, dose and time is right. Never change how you take a medicine because of this app; ask your doctor or pharmacist."
}

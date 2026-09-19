import Foundation

public enum CardioKind: String, Codable, CaseIterable, Sendable {
    case treadmill, stepper, cycle, elliptical, rower, walk, run

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardioKind(rawValue: raw) ?? .treadmill
    }

    public var name: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .stepper: return "Stepper"
        case .cycle: return "Cycle"
        case .elliptical: return "Elliptical"
        case .rower: return "Rower"
        case .walk: return "Walk"
        case .run: return "Run"
        }
    }

    public var symbolName: String {
        switch self {
        case .treadmill, .run: return "figure.run"
        case .stepper: return "figure.stairs"
        case .cycle: return "figure.outdoor.cycle"
        case .elliptical: return "figure.elliptical"
        case .rower: return "figure.rower"
        case .walk: return "figure.walk"
        }
    }

    /// Whether distance makes sense for this machine.
    public var tracksDistance: Bool { self != .stepper }
}

public enum CardioIntensity: String, Codable, CaseIterable, Sendable {
    case easy, moderate, hard

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardioIntensity(rawValue: raw) ?? .moderate
    }

    public var label: String { rawValue.capitalized }
}

/// One stretch on a machine, alongside the sets.
public struct CardioEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: CardioKind
    public var minutes: Int
    /// In the session's distance unit (mi when lifting in lb, km in kg).
    public var distance: Double?
    public var intensity: CardioIntensity
    /// Typed from the machine's display, or estimated from the profile.
    public var calories: Int?
    public var completedAt: Date?

    public init(id: UUID = UUID(), kind: CardioKind, minutes: Int = 0, distance: Double? = nil,
                intensity: CardioIntensity = .moderate, calories: Int? = nil, completedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
        self.distance = distance
        self.intensity = intensity
        self.calories = calories
        self.completedAt = completedAt
    }

    public var holdsUserData: Bool { completedAt != nil || minutes > 0 || (distance ?? 0) > 0 }
}

/// Height, weight and the rest, for calorie estimates. Stored metric;
/// shown in the unit the lifter uses.
public struct BodyProfile: Codable, Equatable, Sendable {
    public var heightCm: Double?
    public var weightKg: Double?
    public var birthYear: Int?
    /// "male" / "female" / nil; only used by the calorie estimate.
    public var sex: String?

    public init(heightCm: Double? = nil, weightKg: Double? = nil, birthYear: Int? = nil, sex: String? = nil) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.birthYear = birthYear
        self.sex = sex
    }

    public var isEmpty: Bool { heightCm == nil && weightKg == nil && birthYear == nil && sex == nil }
}

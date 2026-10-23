import Foundation

// Can I Pet Dat Dog (Wes, 2026-10-22: "a widget focused on a dog lover
// audience … more playful … add your doggie picture, health records,
// insurance, and favorite dog places. But also send me daily funny dog
// things. Let other users join the community of dogs").
//
// Two halves:
// - The community (`/api/widgets/dogs`): dog profiles, Dog Park posts, pets,
//   comments and the Daily Dog. Server shapes below.
// - The private records (`DogsState`, the widget's own document): health,
//   vet, insurance and favorite places. Never sent to the community side;
//   vet documents and insurance-card photos stay on this phone.

// MARK: - Community (server shapes)

/// A dog as the community sees it: no health, no insurance.
public struct DogProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var ownerId: String
    public var ownerName: String
    public var ownerPhotoUrl: String?
    public var name: String
    public var breed: String
    /// "YYYY-MM-DD"
    public var birthday: String?
    /// "YYYY-MM-DD", the day they came home
    public var gotchaDay: String?
    /// "Professional sock thief"
    public var personality: String
    public var photoUrl: String?
    public var postCount: Int

    public init(id: String, ownerId: String = "", ownerName: String = "", ownerPhotoUrl: String? = nil, name: String,
                breed: String = "", birthday: String? = nil, gotchaDay: String? = nil, personality: String = "",
                photoUrl: String? = nil, postCount: Int = 0) {
        self.id = id; self.ownerId = ownerId; self.ownerName = ownerName; self.ownerPhotoUrl = ownerPhotoUrl
        self.name = name; self.breed = breed; self.birthday = birthday; self.gotchaDay = gotchaDay
        self.personality = personality; self.photoUrl = photoUrl; self.postCount = postCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName) ?? ""
        ownerPhotoUrl = try c.decodeIfPresent(String.self, forKey: .ownerPhotoUrl)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Good dog"
        breed = try c.decodeIfPresent(String.self, forKey: .breed) ?? ""
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday).flatMap(DogDay.normalized)
        gotchaDay = try c.decodeIfPresent(String.self, forKey: .gotchaDay).flatMap(DogDay.normalized)
        personality = try c.decodeIfPresent(String.self, forKey: .personality) ?? ""
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        postCount = try c.decodeIfPresent(Int.self, forKey: .postCount) ?? 0
    }

    public var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }

    /// The request body for create / edit (nil fields are cleared).
    public var body: [String: Any] {
        [
            "name": name, "breed": breed, "personality": personality,
            "birthday": birthday ?? NSNull(), "gotchaDay": gotchaDay ?? NSNull(),
            "photoUrl": photoUrl ?? NSNull()
        ]
    }
}

/// Which dogs a post shows.
public struct DogRef: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var breed: String?

    public init(id: String, name: String, breed: String? = nil) { self.id = id; self.name = name; self.breed = breed }
}

public enum DogPostKind: String, Codable, Sendable {
    case photo, video

    public init(from decoder: Decoder) throws {
        self = DogPostKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .photo
    }
}

/// One Dog Park post: a photo or a short clip.
public struct DogPost: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var authorId: String
    public var authorName: String
    public var authorPhotoUrl: String?
    public var caption: String
    public var dogs: [DogRef]
    public var kind: DogPostKind
    public var photoUrl: String?
    public var thumbUrl: String?
    public var videoUrl: String?
    public var posterUrl: String?
    public var durationSec: Double?
    public var petCount: Int
    public var iPetted: Bool
    public var commentCount: Int
    public var createdAt: Date?
    public var mine: Bool
    public var shareUrl: String?

    public init(id: String, authorId: String = "", authorName: String = "", authorPhotoUrl: String? = nil, caption: String = "",
                dogs: [DogRef] = [], kind: DogPostKind = .photo, photoUrl: String? = nil, thumbUrl: String? = nil,
                videoUrl: String? = nil, posterUrl: String? = nil, durationSec: Double? = nil, petCount: Int = 0,
                iPetted: Bool = false, commentCount: Int = 0, createdAt: Date? = nil, mine: Bool = false, shareUrl: String? = nil) {
        self.id = id; self.authorId = authorId; self.authorName = authorName; self.authorPhotoUrl = authorPhotoUrl
        self.caption = caption; self.dogs = dogs; self.kind = kind; self.photoUrl = photoUrl; self.thumbUrl = thumbUrl
        self.videoUrl = videoUrl; self.posterUrl = posterUrl; self.durationSec = durationSec; self.petCount = petCount
        self.iPetted = iPetted; self.commentCount = commentCount; self.createdAt = createdAt; self.mine = mine; self.shareUrl = shareUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        authorPhotoUrl = try c.decodeIfPresent(String.self, forKey: .authorPhotoUrl)
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        dogs = try c.decodeIfPresent([DogRef].self, forKey: .dogs) ?? []
        kind = try c.decodeIfPresent(DogPostKind.self, forKey: .kind) ?? .photo
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        thumbUrl = try c.decodeIfPresent(String.self, forKey: .thumbUrl)
        videoUrl = try c.decodeIfPresent(String.self, forKey: .videoUrl)
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
        durationSec = try c.decodeIfPresent(Double.self, forKey: .durationSec)
        petCount = try c.decodeIfPresent(Int.self, forKey: .petCount) ?? 0
        iPetted = try c.decodeIfPresent(Bool.self, forKey: .iPetted) ?? false
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        shareUrl = try c.decodeIfPresent(String.self, forKey: .shareUrl)
    }

    public var isVideo: Bool { kind == .video && videoUrl != nil }

    /// The picture to show in the feed: the photo, or a clip's poster.
    public var displayURL: URL? {
        (isVideo ? (posterUrl ?? thumbUrl) : (photoUrl ?? thumbUrl)).flatMap(URL.init(string:))
    }

    public var thumbnailURL: URL? { (thumbUrl ?? posterUrl ?? photoUrl).flatMap(URL.init(string:)) }

    /// "Biscuit", "Biscuit & Pepper", "Biscuit, Pepper & Moose"
    public var dogNames: String? { DogCopy.names(dogs.map(\.name)) }

    /// The tap: flip mine and move the count, before the server answers.
    public func togglingPet() -> DogPost {
        var copy = self
        copy.iPetted.toggle()
        copy.petCount = max(0, petCount + (copy.iPetted ? 1 : -1))
        return copy
    }

    /// The link a share carries: the server's, else the widget's own.
    public var linkURL: URL? { shareUrl.flatMap(URL.init(string:)) ?? DogShareLink.post(id) }
}

public struct DogComment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var authorId: String
    public var authorName: String
    public var authorPhotoUrl: String?
    public var text: String
    public var createdAt: Date?
    public var mine: Bool

    public init(id: String, authorId: String = "", authorName: String = "", authorPhotoUrl: String? = nil, text: String,
                createdAt: Date? = nil, mine: Bool = false) {
        self.id = id; self.authorId = authorId; self.authorName = authorName; self.authorPhotoUrl = authorPhotoUrl
        self.text = text; self.createdAt = createdAt; self.mine = mine
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        authorPhotoUrl = try c.decodeIfPresent(String.self, forKey: .authorPhotoUrl)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
    }
}

public enum DailyDogKind: String, Codable, Sendable {
    case dogOfTheDay, joke, fact, line

    public init(from decoder: Decoder) throws {
        self = DailyDogKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .line
    }

    public var label: String {
        switch self {
        case .dogOfTheDay: return "Dog of the Day"
        case .joke: return "Dog joke"
        case .fact: return "Dog fact"
        case .line: return "Daily Dog"
        }
    }

    public var emoji: String {
        switch self {
        case .dogOfTheDay: return "🏆"
        case .joke: return "😂"
        case .fact: return "🤓"
        case .line: return "🐶"
        }
    }
}

/// One Daily Dog: the community's most-petted post, or a funny line.
public struct DailyDog: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    /// "YYYY-MM-DD"
    public var date: String
    public var kind: DailyDogKind
    public var text: String
    public var post: DogPost?
    public var shareUrl: String?
    /// When it was sent to this person (`GET dogs/daily` rows); the paging cursor.
    public var sentAt: Date?

    public init(id: String, date: String, kind: DailyDogKind, text: String, post: DogPost? = nil, shareUrl: String? = nil, sentAt: Date? = nil) {
        self.id = id; self.date = date; self.kind = kind; self.text = text; self.post = post; self.shareUrl = shareUrl; self.sentAt = sentAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        kind = try c.decodeIfPresent(DailyDogKind.self, forKey: .kind) ?? .line
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        post = try? c.decodeIfPresent(DogPost.self, forKey: .post)
        shareUrl = try c.decodeIfPresent(String.self, forKey: .shareUrl)
        sentAt = try? c.decodeIfPresent(Date.self, forKey: .sentAt)
    }

    public var linkURL: URL? { shareUrl.flatMap(URL.init(string:)) ?? DogShareLink.daily(id) }
}

/// When the Daily Dog arrives.
public struct DogDailyPrefs: Codable, Equatable, Sendable {
    public static let maxTimes = 3
    public var enabled: Bool
    /// "HH:mm", local
    public var times: [String]

    public init(enabled: Bool = false, times: [String] = ["09:00"]) { self.enabled = enabled; self.times = times }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let raw = try c.decodeIfPresent([String].self, forKey: .times) ?? []
        times = raw.isEmpty ? ["09:00"] : raw
    }
}

/// GET dogs/me
public struct DogsMe: Decodable, Equatable, Sendable {
    public var member: Bool
    /// False when this app build is too old for the server's Dog Park
    public var minVersionOk: Bool
    public var dogs: [DogProfile]
    public var prefs: DogDailyPrefs
    public var today: DailyDog?

    public init(member: Bool = false, minVersionOk: Bool = true, dogs: [DogProfile] = [], prefs: DogDailyPrefs = DogDailyPrefs(), today: DailyDog? = nil) {
        self.member = member; self.minVersionOk = minVersionOk; self.dogs = dogs; self.prefs = prefs; self.today = today
    }

    enum CodingKeys: String, CodingKey { case member, minVersionOk, dogs, prefs, today }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        member = try c.decodeIfPresent(Bool.self, forKey: .member) ?? false
        minVersionOk = try c.decodeIfPresent(Bool.self, forKey: .minVersionOk) ?? true
        dogs = try c.decodeIfPresent([DogProfile].self, forKey: .dogs) ?? []
        prefs = try c.decodeIfPresent(DogDailyPrefs.self, forKey: .prefs) ?? DogDailyPrefs()
        today = try? c.decodeIfPresent(DailyDog.self, forKey: .today)
    }
}

public enum DogFeedTab: String, CaseIterable, Identifiable, Sendable {
    case today, top, following
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .today: return "Today"
        case .top: return "Top this week"
        case .following: return "Following"
        }
    }
}

// MARK: - Import from your vet (the scan's draft)

/// What the vet-record scan read. Every row may be flagged `unsure`; the
/// person checks it before anything is saved.
public struct DogRecordDraft: Decodable, Equatable, Sendable {
    public struct Vaccine: Decodable, Equatable, Hashable, Sendable {
        public var name: String
        public var givenOn: String?
        public var dueOn: String?
        public var notes: String?
        public var unsure: Bool
        public init(name: String, givenOn: String? = nil, dueOn: String? = nil, notes: String? = nil, unsure: Bool = false) {
            self.name = name; self.givenOn = givenOn; self.dueOn = dueOn; self.notes = notes; self.unsure = unsure
        }
    }
    public struct Visit: Decodable, Equatable, Hashable, Sendable {
        public var date: String?
        public var clinic: String?
        public var reason: String?
        public var notes: String?
        public var unsure: Bool
        public init(date: String? = nil, clinic: String? = nil, reason: String? = nil, notes: String? = nil, unsure: Bool = false) {
            self.date = date; self.clinic = clinic; self.reason = reason; self.notes = notes; self.unsure = unsure
        }
    }
    public struct Medication: Decodable, Equatable, Hashable, Sendable {
        public var name: String
        public var dose: String?
        public var schedule: String?
        public var startedOn: String?
        public var endsOn: String?
        public var unsure: Bool
        public init(name: String, dose: String? = nil, schedule: String? = nil, startedOn: String? = nil, endsOn: String? = nil, unsure: Bool = false) {
            self.name = name; self.dose = dose; self.schedule = schedule; self.startedOn = startedOn; self.endsOn = endsOn; self.unsure = unsure
        }
    }
    public struct Weight: Decodable, Equatable, Hashable, Sendable {
        public var date: String?
        public var lbs: Double
        public var unsure: Bool
        public init(date: String? = nil, lbs: Double, unsure: Bool = false) { self.date = date; self.lbs = lbs; self.unsure = unsure }
    }

    public var petName: String?
    public var vaccines: [Vaccine]
    public var vetVisits: [Visit]
    public var medications: [Medication]
    public var weights: [Weight]
    public var vet: DogVet?
    public var notes: String?

    public init(petName: String? = nil, vaccines: [Vaccine] = [], vetVisits: [Visit] = [], medications: [Medication] = [],
                weights: [Weight] = [], vet: DogVet? = nil, notes: String? = nil) {
        self.petName = petName; self.vaccines = vaccines; self.vetVisits = vetVisits; self.medications = medications
        self.weights = weights; self.vet = vet; self.notes = notes
    }

    public var isEmpty: Bool { vaccines.isEmpty && vetVisits.isEmpty && medications.isEmpty && weights.isEmpty && (vet?.isEmpty ?? true) }
}

// Lenient row decoding: a missing `unsure` is false, odd dates are dropped.
extension DogRecordDraft.Vaccine {
    enum CodingKeys: String, CodingKey { case name, givenOn, dueOn, notes, unsure }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        givenOn = try c.decodeIfPresent(String.self, forKey: .givenOn).flatMap(DogDay.normalized)
        dueOn = try c.decodeIfPresent(String.self, forKey: .dueOn).flatMap(DogDay.normalized)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        unsure = try c.decodeIfPresent(Bool.self, forKey: .unsure) ?? false
    }
}

extension DogRecordDraft.Visit {
    enum CodingKeys: String, CodingKey { case date, clinic, reason, notes, unsure }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date).flatMap(DogDay.normalized)
        clinic = try c.decodeIfPresent(String.self, forKey: .clinic)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        unsure = try c.decodeIfPresent(Bool.self, forKey: .unsure) ?? false
    }
}

extension DogRecordDraft.Medication {
    enum CodingKeys: String, CodingKey { case name, dose, schedule, startedOn, endsOn, unsure }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        dose = try c.decodeIfPresent(String.self, forKey: .dose)
        schedule = try c.decodeIfPresent(String.self, forKey: .schedule)
        startedOn = try c.decodeIfPresent(String.self, forKey: .startedOn).flatMap(DogDay.normalized)
        endsOn = try c.decodeIfPresent(String.self, forKey: .endsOn).flatMap(DogDay.normalized)
        unsure = try c.decodeIfPresent(Bool.self, forKey: .unsure) ?? false
    }
}

extension DogRecordDraft.Weight {
    enum CodingKeys: String, CodingKey { case date, lbs, unsure }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date).flatMap(DogDay.normalized)
        lbs = try c.decodeIfPresent(Double.self, forKey: .lbs) ?? 0
        unsure = try c.decodeIfPresent(Bool.self, forKey: .unsure) ?? false
    }
}

extension DogRecordDraft {
    enum CodingKeys: String, CodingKey { case petName, vaccines, vetVisits, medications, weights, vet, notes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        petName = try c.decodeIfPresent(String.self, forKey: .petName)
        vaccines = (try c.decodeIfPresent([Vaccine].self, forKey: .vaccines) ?? []).filter { !$0.name.isEmpty }
        vetVisits = try c.decodeIfPresent([Visit].self, forKey: .vetVisits) ?? []
        medications = (try c.decodeIfPresent([Medication].self, forKey: .medications) ?? []).filter { !$0.name.isEmpty }
        weights = (try c.decodeIfPresent([Weight].self, forKey: .weights) ?? []).filter { $0.lbs > 0 }
        vet = try? c.decodeIfPresent(DogVet.self, forKey: .vet)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Private records (the widget's own document)

public struct DogVaccine: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// "YYYY-MM-DD"
    public var givenOn: String?
    public var dueOn: String?
    public var notes: String

    public init(id: String = UUID().uuidString, name: String, givenOn: String? = nil, dueOn: String? = nil, notes: String = "") {
        self.id = id; self.name = name; self.givenOn = givenOn; self.dueOn = dueOn; self.notes = notes
    }
}

public struct DogVetVisit: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var date: String?
    public var clinic: String
    public var reason: String
    public var notes: String

    public init(id: String = UUID().uuidString, date: String? = nil, clinic: String = "", reason: String = "", notes: String = "") {
        self.id = id; self.date = date; self.clinic = clinic; self.reason = reason; self.notes = notes
    }
}

public struct DogMedication: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var dose: String
    /// "Monthly", "Twice a day" — free text
    public var schedule: String
    public var startedOn: String?
    public var endsOn: String?

    public init(id: String = UUID().uuidString, name: String, dose: String = "", schedule: String = "",
                startedOn: String? = nil, endsOn: String? = nil) {
        self.id = id; self.name = name; self.dose = dose; self.schedule = schedule; self.startedOn = startedOn; self.endsOn = endsOn
    }
}

public struct DogWeight: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var date: String
    public var lbs: Double

    public init(id: String = UUID().uuidString, date: String, lbs: Double) { self.id = id; self.date = date; self.lbs = lbs }
}

public struct DogVet: Codable, Equatable, Hashable, Sendable {
    public var clinic: String
    public var phone: String
    public var address: String

    public init(clinic: String = "", phone: String = "", address: String = "") { self.clinic = clinic; self.phone = phone; self.address = address }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clinic = try c.decodeIfPresent(String.self, forKey: .clinic) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
    }

    public var isEmpty: Bool { clinic.isEmpty && phone.isEmpty && address.isEmpty }
}

public struct DogInsurance: Codable, Equatable, Hashable, Sendable {
    public var provider: String
    public var policyNumber: String
    public var claimsPhone: String
    /// The card's photo is a file on this phone (`DogLocalPhotos`)
    public var cardPhoto: String?

    public init(provider: String = "", policyNumber: String = "", claimsPhone: String = "", cardPhoto: String? = nil) {
        self.provider = provider; self.policyNumber = policyNumber; self.claimsPhone = claimsPhone; self.cardPhoto = cardPhoto
    }

    public var isEmpty: Bool { provider.isEmpty && policyNumber.isEmpty && claimsPhone.isEmpty && cardPhoto == nil }
}

/// A favorite dog spot (saved to the "Dog spots" circle as well).
public struct DogFavoritePlace: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var address: String?
    public var placeId: String?
    public var savedAt: Date

    public init(id: String = UUID().uuidString, name: String, address: String? = nil, placeId: String? = nil, savedAt: Date = Date()) {
        self.id = id; self.name = name; self.address = address; self.placeId = placeId; self.savedAt = savedAt
    }
}

/// A vet document kept with a dog's records (Wes, 2026-10-23: "allow user
/// to simply add the document to the dogs records … for easy viewing"):
/// photos of the pages, or the PDF the vet emailed. The files live on this
/// phone (`DogLocalPhotos`); the record keeps their names.
public struct DogDocument: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case photos, pdf }

    public var id: String
    public var title: String
    public var kind: Kind
    /// File names: one per photographed page, or the one PDF
    public var files: [String]
    public var addedAt: Date

    public init(id: String = UUID().uuidString, title: String, kind: Kind, files: [String], addedAt: Date = Date()) {
        self.id = id; self.title = title; self.kind = kind; self.files = files; self.addedAt = addedAt
    }

    public static let defaultTitle = "Vet paperwork"
    static let legacyCertificateTitle = "Vaccine certificate"

    /// "Invoice 103109.pdf" → "Invoice 103109"; blank → "Vet paperwork"
    public static func title(fromFileName name: String?) -> String {
        let base = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = base.lowercased().hasSuffix(".pdf") ? String(base.dropLast(4)) : base
        let clean = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? defaultTitle : String(clean.prefix(80))
    }
}

/// Everything private about one dog.
public struct DogRecords: Codable, Equatable, Sendable {
    public var vaccines: [DogVaccine]
    public var vetVisits: [DogVetVisit]
    public var medications: [DogMedication]
    public var weights: [DogWeight]
    public var vet: DogVet
    public var insurance: DogInsurance
    /// Vet paperwork, certificates, invoices: files on this phone, newest last
    public var documents: [DogDocument]

    public init(vaccines: [DogVaccine] = [], vetVisits: [DogVetVisit] = [], medications: [DogMedication] = [], weights: [DogWeight] = [],
                vet: DogVet = DogVet(), insurance: DogInsurance = DogInsurance(), documents: [DogDocument] = []) {
        self.vaccines = vaccines; self.vetVisits = vetVisits; self.medications = medications; self.weights = weights
        self.vet = vet; self.insurance = insurance; self.documents = documents
    }

    private enum CodingKeys: String, CodingKey {
        case vaccines, vetVisits, medications, weights, vet, insurance, documents
        /// 0.53.0 kept vaccine-certificate photos as bare file names
        case certificatePhotos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vaccines = try c.decodeIfPresent([DogVaccine].self, forKey: .vaccines) ?? []
        vetVisits = try c.decodeIfPresent([DogVetVisit].self, forKey: .vetVisits) ?? []
        medications = try c.decodeIfPresent([DogMedication].self, forKey: .medications) ?? []
        weights = try c.decodeIfPresent([DogWeight].self, forKey: .weights) ?? []
        vet = try c.decodeIfPresent(DogVet.self, forKey: .vet) ?? DogVet()
        insurance = try c.decodeIfPresent(DogInsurance.self, forKey: .insurance) ?? DogInsurance()
        var docs = try c.decodeIfPresent([DogDocument].self, forKey: .documents) ?? []
        let legacy = try c.decodeIfPresent([String].self, forKey: .certificatePhotos) ?? []
        let known = Set(docs.map(\.id))
        // The file name doubles as the id, so a re-read never duplicates one
        docs += legacy.filter { !known.contains($0) }.map {
            DogDocument(id: $0, title: DogDocument.legacyCertificateTitle, kind: .photos, files: [$0], addedAt: Date(timeIntervalSince1970: 0))
        }
        documents = docs
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vaccines, forKey: .vaccines)
        try c.encode(vetVisits, forKey: .vetVisits)
        try c.encode(medications, forKey: .medications)
        try c.encode(weights, forKey: .weights)
        try c.encode(vet, forKey: .vet)
        try c.encode(insurance, forKey: .insurance)
        try c.encode(documents, forKey: .documents)
    }

    public var isEmpty: Bool {
        vaccines.isEmpty && vetVisits.isEmpty && medications.isEmpty && weights.isEmpty && vet.isEmpty && insurance.isEmpty && documents.isEmpty
    }

    public var latestWeight: DogWeight? { weights.max { $0.date < $1.date } }
}

/// The widget's private document: records per dog id, favorite places and
/// the reminder switch. Never pruned; a removed dog's records stay.
public struct DogsState: WidgetModel {
    public static let schemaVersion = 1
    public var records: [String: DogRecords]
    public var places: [DogFavoritePlace]
    /// Vaccine-due, birthday and gotcha-day notifications on this phone
    public var remindersOn: Bool

    public init(records: [String: DogRecords] = [:], places: [DogFavoritePlace] = [], remindersOn: Bool = true) {
        self.records = records; self.places = places; self.remindersOn = remindersOn
    }

    public static let empty = DogsState()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([String: DogRecords].self, forKey: .records) ?? [:]
        places = try c.decodeIfPresent([DogFavoritePlace].self, forKey: .places) ?? []
        remindersOn = try c.decodeIfPresent(Bool.self, forKey: .remindersOn) ?? true
    }

    public func records(for dogId: String) -> DogRecords { records[dogId] ?? DogRecords() }

    /// Two phones saved: keep every row from both (by id, local wins on the
    /// same row), and the local single fields.
    public static func merge(local: DogsState, remote: DogsState) -> DogsState {
        var out = local
        for (dogId, theirs) in remote.records {
            guard let mine = local.records[dogId] else { out.records[dogId] = theirs; continue }
            var merged = mine
            merged.vaccines = union(mine.vaccines, theirs.vaccines)
            merged.vetVisits = union(mine.vetVisits, theirs.vetVisits)
            merged.medications = union(mine.medications, theirs.medications)
            merged.weights = union(mine.weights, theirs.weights)
            merged.documents = union(mine.documents, theirs.documents)
            if mine.vet.isEmpty { merged.vet = theirs.vet }
            if mine.insurance.isEmpty { merged.insurance = theirs.insurance }
            out.records[dogId] = merged
        }
        out.places = union(local.places, remote.places)
        return out
    }

    private static func union<T: Identifiable>(_ mine: [T], _ theirs: [T]) -> [T] where T.ID == String {
        let ids = Set(mine.map(\.id))
        return mine + theirs.filter { !ids.contains($0.id) }
    }
}

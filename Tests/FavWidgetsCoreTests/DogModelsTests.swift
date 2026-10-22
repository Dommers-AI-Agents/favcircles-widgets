import Foundation
import Testing
@testable import FavWidgetsCore

/// Can I Pet Dat Dog (Wes, 2026-10-22): the server's shapes, the words, the
/// vaccine and birthday reminders, and folding a vet-record scan in.
struct DogModelsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ day: String, _ hour: Int = 12) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: DogDay.date(day, calendar: calendar)!)!
    }

    // MARK: Decoding

    @Test func decodesTheFeedAndToleratesMissingAndNewFields() throws {
        let json = """
        {"posts":[
          {"id":"p1","authorId":"u1","authorName":"Ana","authorPhotoUrl":null,"caption":"Zoomies","dogs":[{"id":"d1","name":"Biscuit","breed":"Corgi"}],
           "kind":"video","photoUrl":null,"thumbUrl":"https://x/t.jpg","videoUrl":"https://x/v.mp4","posterUrl":"https://x/p.jpg","durationSec":12.5,
           "petCount":23,"iPetted":true,"commentCount":2,"createdAt":"2026-10-22T13:00:00.000Z","mine":false,"shareUrl":"https://api.favcircles.com/app/widget/dogs?post=p1","future":1},
          {"id":"p2","kind":"hologram","photoUrl":"https://x/a.jpg"}
        ],"hasMore":true}
        """
        struct Page: Decodable { let posts: [DogPost]; let hasMore: Bool }
        let page = try WidgetJSON.decode(Page.self, from: Data(json.utf8))
        #expect(page.hasMore && page.posts.count == 2)
        let v = page.posts[0]
        #expect(v.isVideo && v.displayURL?.absoluteString == "https://x/p.jpg" && v.petCount == 23 && v.iPetted)
        #expect(v.dogNames == "Biscuit" && v.createdAt != nil)
        let p = page.posts[1]
        #expect(p.kind == .photo && !p.isVideo && p.petCount == 0 && p.dogs.isEmpty)
        #expect(p.displayURL?.absoluteString == "https://x/a.jpg")
        #expect(p.linkURL?.absoluteString == "https://api.favcircles.com/app/widget/dogs?post=p2")
    }

    @Test func decodesMeWithTodayAndDefaults() throws {
        let json = """
        {"member":true,"dogs":[{"id":"d1","ownerId":"u0","ownerName":"Wes","name":"Biscuit","breed":"Corgi","birthday":"2021-06-01T00:00:00Z","personality":"Sock thief","postCount":3}],
         "prefs":{"enabled":true,"times":[]},
         "today":{"id":"2026-10-22","date":"2026-10-22","kind":"dogOfTheDay","text":"Most petted yesterday","post":{"id":"p9","photoUrl":"https://x/9.jpg","petCount":41}}}
        """
        let me = try WidgetJSON.decode(DogsMe.self, from: Data(json.utf8))
        #expect(me.member && me.minVersionOk && me.dogs.first?.birthday == "2021-06-01")
        #expect(me.prefs.enabled && me.prefs.times == ["09:00"])
        #expect(me.today?.kind == .dogOfTheDay && me.today?.post?.petCount == 41)
        #expect(me.today?.linkURL?.absoluteString == "https://api.favcircles.com/app/widget/dogs?daily=2026-10-22")
        let empty = try WidgetJSON.decode(DogsMe.self, from: Data("{}".utf8))
        #expect(!empty.member && empty.dogs.isEmpty && empty.today == nil && !empty.prefs.enabled)
    }

    @Test func decodesAScanDraftAndDropsEmptyRows() throws {
        let json = """
        {"petName":"Biscuit","vaccines":[{"name":"Rabies (3 yr)","givenOn":"2025-04-02","dueOn":"2028-04-02"},{"name":"","givenOn":"2025-01-01"},
           {"name":"Bordetella","givenOn":"2025/04/02","dueOn":"2026-04-02","unsure":true}],
         "vetVisits":[{"date":"2025-04-02","clinic":"Dilworth Animal Hospital","reason":"Annual exam"}],
         "medications":[{"name":"Heartgard Plus","dose":"26-50 lb","schedule":"Monthly"}],
         "weights":[{"date":"2025-04-02","lbs":28.4},{"date":"2025-05-01","lbs":0}],
         "vet":{"clinic":"Dilworth Animal Hospital","phone":"704-555-0100"}}
        """
        let draft = try WidgetJSON.decode(DogRecordDraft.self, from: Data(json.utf8))
        #expect(draft.vaccines.count == 2)
        #expect(draft.vaccines[1].givenOn == nil && draft.vaccines[1].unsure)  // odd date dropped, flag kept
        #expect(draft.weights.count == 1 && draft.medications.first?.schedule == "Monthly")
        #expect(draft.vet?.phone == "704-555-0100" && draft.vet?.address == "")
        #expect(!draft.isEmpty)
    }

    // MARK: Words

    @Test func agesAndNames() {
        let now = at("2026-10-22")
        #expect(DogCopy.age(birthday: "2023-10-01", now: now, calendar: calendar) == "3 yrs")
        #expect(DogCopy.age(birthday: "2025-10-01", now: now, calendar: calendar) == "1 yr")
        #expect(DogCopy.age(birthday: "2026-03-10", now: now, calendar: calendar) == "7 mo")
        #expect(DogCopy.age(birthday: "2026-10-10", now: now, calendar: calendar) == "New pup")
        #expect(DogCopy.age(birthday: "2027-01-01", now: now, calendar: calendar) == nil)
        #expect(DogCopy.age(birthday: nil, now: now, calendar: calendar) == nil)
        #expect(DogCopy.names(["Biscuit", "Pepper", "Moose"]) == "Biscuit, Pepper & Moose")
        #expect(DogCopy.names(["Biscuit", " "]) == "Biscuit")
        #expect(DogCopy.petted(0) == "Be the first to pet" && DogCopy.petted(1) == "Petted once" && DogCopy.petted(23) == "Petted 23 times")
        let dog = DogProfile(id: "d", name: "Biscuit", breed: "Corgi", birthday: "2023-10-01")
        #expect(DogCopy.subtitle(dog, now: now, calendar: calendar) == "Corgi · 3 yrs")
    }

    @Test func dayStrings() {
        #expect(DogDay.normalized("2024-3-5") == "2024-03-05")
        #expect(DogDay.normalized("2024-03-05T10:00:00Z") == "2024-03-05")
        #expect(DogDay.normalized("2024/03/05") == nil && DogDay.normalized("2024-13-01") == nil && DogDay.normalized("") == nil)
        #expect(DogDay.display("2024-03-05", calendar: calendar) == "Mar 5, 2024")
        #expect(DogDay.daysUntil("2026-10-25", from: at("2026-10-22", 23), calendar: calendar) == 3)
    }

    @Test func petToggleMovesTheCount() {
        let post = DogPost(id: "p", petCount: 4)
        let petted = post.togglingPet()
        #expect(petted.iPetted && petted.petCount == 5)
        let unpetted = petted.togglingPet()
        #expect(!unpetted.iPetted && unpetted.petCount == 4)
        #expect(DogPost(id: "q", petCount: 0, iPetted: true).togglingPet().petCount == 0)
    }

    // MARK: Vaccines

    @Test func vaccineStatus() {
        let now = at("2026-10-22")
        func status(_ due: String?) -> DogVaccineStatus { .of(DogVaccine(name: "Rabies", dueOn: due), now: now, calendar: calendar) }
        #expect(status(nil) == .noDueDate)
        #expect(status("2027-06-01") == .ok(days: 222) && !status("2027-06-01").needsAttention)
        #expect(status("2026-11-05") == .dueSoon(days: 14) && status("2026-11-05").text == "Due in 14 days")
        #expect(status("2026-10-22") == .dueToday)
        #expect(status("2026-10-19") == .overdue(days: 3) && status("2026-10-19").needsAttention)
        #expect(status("2026-10-23").text == "Due tomorrow")
    }

    // MARK: Reminders

    @Test func remindersForVaccinesBirthdaysAndGotchaDays() {
        let now = at("2026-10-22")
        let dog = DogProfile(id: "d1", name: "Biscuit", birthday: "2021-11-01", gotchaDay: "2022-01-15")
        var state = DogsState()
        state.records["d1"] = DogRecords(vaccines: [
            DogVaccine(id: "v1", name: "Rabies", dueOn: "2026-12-01"),   // 30 d before = Nov 1, 7 d = Nov 24
            DogVaccine(id: "v2", name: "Bordetella", dueOn: "2026-11-10") // 30 d before passed; 7 d = Nov 3
        ])
        let plan = DogReminderPlan.reminders(dogs: [dog], state: state, now: now, calendar: calendar)
        let ids = plan.map(\.id)
        #expect(ids.contains("dogs-vax-d1-v1-30") && ids.contains("dogs-vax-d1-v1-7") && ids.contains("dogs-vax-d1-v2-7"))
        #expect(!ids.contains("dogs-vax-d1-v2-30"))
        let bday = plan.first { $0.id == "dogs-bday-d1" }
        #expect(bday?.title == "🎂 Biscuit turns 5 today!")
        #expect(bday?.fireAt == calendar.date(bySettingHour: 9, minute: 0, second: 0, of: DogDay.date("2026-11-01", calendar: calendar)!))
        let gotcha = plan.first { $0.id == "dogs-gotcha-d1" }
        #expect(gotcha?.body == "5 years home today. Best day ever." && calendar.component(.year, from: gotcha!.fireAt) == 2027)
        #expect(plan == plan.sorted { $0.fireAt < $1.fireAt })

        state.remindersOn = false
        #expect(DogReminderPlan.reminders(dogs: [dog], state: state, now: now, calendar: calendar).isEmpty)
    }

    @Test func quietHoursMoveTheReminderAndLeapBirthdaysLand() {
        let quiet = WidgetQuietHours(startMinutes: 22 * 60, endMinutes: 10 * 60 + 30)
        let dog = DogProfile(id: "d", name: "Leap", birthday: "2024-02-29")
        let plan = DogReminderPlan.reminders(dogs: [dog], state: DogsState(), now: at("2026-10-22"), calendar: calendar, quietHours: quiet)
        let fire = plan.first!.fireAt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        #expect(c.year == 2027 && c.month == 2 && c.day == 28 && c.hour == 10 && c.minute == 30)
        #expect(plan.first!.title == "🎂 Leap turns 3 today!")
        // Today's birthday still counts when it's earlier in the day
        let today = DogReminderPlan.nextAnniversary(of: "2020-10-22", after: at("2026-10-22", 8), calendar: calendar)
        #expect(today?.years == 6)
    }

    // MARK: Import from your vet

    @Test func mergeAddsOnlyWhatsNewAndNeverOverwritesTypedFields() {
        var existing = DogRecords(vaccines: [DogVaccine(id: "a", name: "Rabies", givenOn: "2025-04-02", dueOn: nil)],
                                  weights: [DogWeight(date: "2025-04-02", lbs: 28)],
                                  vet: DogVet(clinic: "My Vet", phone: "", address: ""))
        existing.medications = [DogMedication(name: "Heartgard Plus", startedOn: nil)]
        let draft = DogRecordDraft(
            vaccines: [.init(name: "rabies", givenOn: "2025-04-02", dueOn: "2028-04-02"),   // fills the due date
                       .init(name: "Rabies", givenOn: "2025-04-02", dueOn: "2028-04-02"),   // now a repeat
                       .init(name: "DHPP", givenOn: "2025-04-02", dueOn: "2026-04-02")],
            vetVisits: [.init(date: "2025-04-02", reason: "Annual exam"), .init(date: "2025-04-02", reason: "annual  exam")],
            medications: [.init(name: "HEARTGARD plus"), .init(name: "NexGard", schedule: "Monthly")],
            weights: [.init(date: "2025-04-02", lbs: 28.4), .init(date: "2025-10-01", lbs: 29), .init(date: nil, lbs: 30)],
            vet: DogVet(clinic: "Dilworth", phone: "704-555-0100", address: "1 Main St")
        )
        let result = DogRecordMerge.merge(draft, into: existing)
        let r = result.records
        #expect(r.vaccines.count == 2 && r.vaccines.first { $0.id == "a" }?.dueOn == "2028-04-02")
        #expect(r.vetVisits.count == 1 && r.medications.count == 2 && r.weights.map(\.date) == ["2025-04-02", "2025-10-01"])
        #expect(r.vet.clinic == "My Vet" && r.vet.phone == "704-555-0100" && r.vet.address == "1 Main St")
        #expect(result.added == 1 + 1 + 1 + 1 + 1 && result.skipped == 1 + 1 + 1 + 2)
    }

    @Test func twoPhonesKeepEveryRow() {
        var local = DogsState()
        local.records["d"] = DogRecords(vaccines: [DogVaccine(id: "1", name: "Rabies")], vet: DogVet(clinic: "Mine"))
        var remote = DogsState(places: [DogFavoritePlace(id: "pl", name: "Freedom Park")])
        remote.records["d"] = DogRecords(vaccines: [DogVaccine(id: "1", name: "Rabies (edited)"), DogVaccine(id: "2", name: "DHPP")],
                                         insurance: DogInsurance(provider: "Trupanion"))
        remote.records["e"] = DogRecords(weights: [DogWeight(date: "2026-01-01", lbs: 12)])
        let merged = DogsState.merge(local: local, remote: remote)
        #expect(merged.records["d"]?.vaccines.map(\.name) == ["Rabies", "DHPP"])
        #expect(merged.records["d"]?.vet.clinic == "Mine" && merged.records["d"]?.insurance.provider == "Trupanion")
        #expect(merged.records["e"]?.weights.count == 1 && merged.places.count == 1)
    }

    @Test func privateDocumentRoundTrips() throws {
        var state = DogsState()
        state.records["d"] = DogRecords(vaccines: [DogVaccine(name: "Rabies", givenOn: "2025-04-02", dueOn: "2028-04-02")],
                                        insurance: DogInsurance(provider: "Lemonade", policyNumber: "LP-1", cardPhoto: "dogs-card-d.jpg"),
                                        certificatePhotos: ["dogs-cert-1.jpg"])
        let back = try WidgetDocumentCodec.decode(DogsState.self, from: WidgetDocumentCodec.encode(state))
        #expect(back == state)
        // An older/empty document reads as empty
        #expect(try WidgetDocumentCodec.decode(DogsState.self, from: Data("{}".utf8)) == .empty)
    }

    @Test func shareLinks() {
        #expect(DogShareLink.post("abc")?.absoluteString == "https://api.favcircles.com/app/widget/dogs?post=abc")
        #expect(DogShareLink.daily("2026-10-22")?.absoluteString == "https://api.favcircles.com/app/widget/dogs?daily=2026-10-22")
        #expect(DogShareLink.post("") == nil)
    }
}

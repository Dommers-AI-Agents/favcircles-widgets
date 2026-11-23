import Testing
import Foundation
@testable import FavWidgetsCore

struct MedLabelScanTests {
    private let reply = """
    {"success":true,"kind":"medLabel","truncated":false,"draft":{"notes":"One label was cut off","medications":[
      {"name":"Metformin HCL","strength":"500 mg","amount":"1 tablet","directions":"Take 1 tablet by mouth twice daily with meals",
       "note":"With meals","frequency":"twice_daily","times":[480,1200],"days":[],"asNeeded":false,"unsure":false,"why":"Suggested times. Change them to fit your day."},
      {"name":"Ibuprofen","strength":"200 mg","amount":null,"directions":"Take as needed for pain","note":null,
       "frequency":"as_needed","times":[],"days":[],"asNeeded":true,"unsure":false,"why":"Take as needed: no reminder unless you add a time."},
      {"name":"Prednisone","frequency":"other","times":[2000,-5],"days":[0,3,9],"unsure":true}
    ]}}
    """

    private func reading() throws -> MedLabelReading {
        try JSONDecoder().decode(MedLabelReading.Response.self, from: Data(reply.utf8)).reading
    }

    @Test func decodesTheServerReply() throws {
        let r = try reading()
        #expect(r.medications.count == 3)
        #expect(r.notes == "One label was cut off")
        #expect(Set(r.medications.map(\.id)).count == 3)
        let p = r.medications[2]
        #expect(p.times.isEmpty)          // out-of-range minutes dropped
        #expect(p.days == [3])            // out-of-range weekdays dropped
        #expect(p.unsure)
    }

    @Test func draftBecomesAMed() throws {
        let m = try reading().medications[0].med()
        #expect(m.name == "Metformin HCL")
        #expect(m.dose == "500 mg · 1 tablet")
        #expect(m.times == [480, 1200])
        #expect(m.note == "With meals")
        #expect(m.active)
        let i = try reading().medications[1].med()
        #expect(i.dose == "200 mg")
        #expect(i.note == "")
    }

    @Test func onlyAReadScheduleIsTickedByDefault() throws {
        let r = try reading()
        #expect(r.medications.map(\.includedByDefault) == [true, false, false])
        #expect(MedLabelScan.canAdd(r.medications[0].med()))
        #expect(!MedLabelScan.canAdd(r.medications[2].med()))
    }

    @Test func refillOfAMedAlreadyListed() {
        let list = [Med(name: "Metformin HCl", dose: "500 mg")]
        #expect(MedLabelScan.existing(MedLabelDraft(name: "metformin  hcl"), in: list) != nil)
        #expect(MedLabelScan.existing(MedLabelDraft(name: "Metoprolol"), in: list) == nil)
    }

    @Test func warningSaysWhoIsResponsible() {
        #expect(MedSafetyCopy.scanWarning.contains("responsible"))
        #expect(MedSafetyCopy.footer.contains("not medical advice"))
    }
}

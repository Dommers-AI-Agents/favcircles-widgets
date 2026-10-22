import SwiftUI
import PhotosUI
import FavWidgetsCore

/// Which private record a sheet edits (nil row = a new one).
enum DogRecordEdit: Identifiable {
    case vaccine(DogVaccine?)
    case visit(DogVetVisit?)
    case medication(DogMedication?)
    case weight(DogWeight?)
    case vet
    case insurance

    var id: String {
        switch self {
        case .vaccine(let v): return "vax-\(v?.id ?? "new")"
        case .visit(let v): return "visit-\(v?.id ?? "new")"
        case .medication(let m): return "med-\(m?.id ?? "new")"
        case .weight(let w): return "weight-\(w?.id ?? "new")"
        case .vet: return "vet"
        case .insurance: return "insurance"
        }
    }

    var title: String {
        switch self {
        case .vaccine(let v): return v == nil ? "Add a vaccine" : "Vaccine"
        case .visit(let v): return v == nil ? "Add a vet visit" : "Vet visit"
        case .medication(let m): return m == nil ? "Add a medication" : "Medication"
        case .weight(let w): return w == nil ? "Add a weight" : "Weight"
        case .vet: return "Your vet"
        case .insurance: return "Insurance"
        }
    }

    var isExisting: Bool {
        switch self {
        case .vaccine(let v): return v != nil
        case .visit(let v): return v != nil
        case .medication(let m): return m != nil
        case .weight(let w): return w != nil
        case .vet, .insurance: return false
        }
    }
}

/// One form for every record kind; saves the whole dog's records back.
struct DogRecordEditor: View {
    let context: WidgetContext
    let edit: DogRecordEdit
    let records: DogRecords
    let onSave: (DogRecords) -> Void
    @Environment(\.dismiss) private var dismiss

    // One set of fields covers every kind
    @State private var name = ""
    @State private var second = ""      // dose / clinic / phone / policy
    @State private var third = ""       // schedule / reason / address / claims phone
    @State private var notes = ""
    @State private var dayA: String?    // given / date / started
    @State private var dayB: String?    // due / ends
    @State private var lbs = ""
    @State private var cardPhoto: String?
    @State private var cardItem: PhotosPickerItem?
    @State private var confirmingDelete = false

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: edit.title, theme: theme, confirm: (label: "Save", enabled: valid, action: save)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fields(theme)
                    if edit.isExisting {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Text("Delete").font(.system(size: 15)).foregroundStyle(theme.danger).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
                .padding(16)
            }
        }
        .onAppear(perform: fill)
        .confirmationDialog("Delete this?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: cardItem) { picked in
            guard let picked else { return }
            Task { @MainActor in
                guard let data = try? await picked.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data),
                      let jpeg = EventImagePrep.jpeg(image), let saved = DogLocalPhotos.save(jpeg, prefix: "dogs-card") else { return }
                if let old = cardPhoto, old != records.insurance.cardPhoto { DogLocalPhotos.delete(old) }
                cardPhoto = saved
            }
        }
    }

    @ViewBuilder
    private func fields(_ theme: WidgetTheme) -> some View {
        switch edit {
        case .vaccine:
            text("Vaccine", $name, "Rabies, DHPP, Bordetella…")
            DogDayField(label: "Given", day: $dayA, accent: context.accent, calendar: context.calendar)
            DogDayField(label: "Due", day: $dayB, accent: context.accent, calendar: context.calendar, allowsFuture: true)
            text("Notes", $notes, "Lot number, clinic…")
        case .visit:
            DogDayField(label: "Date", day: $dayA, accent: context.accent, calendar: context.calendar)
            text("Reason", $third, "Annual checkup")
            text("Clinic", $second, records.vet.clinic.isEmpty ? "Clinic name" : records.vet.clinic)
            text("Notes", $notes, "What the vet said")
        case .medication:
            text("Medication", $name, "Heartgard Plus")
            text("Dose", $second, "26–50 lb, 1 chew")
            text("How often", $third, "Monthly")
            DogDayField(label: "Started", day: $dayA, accent: context.accent, calendar: context.calendar)
            DogDayField(label: "Ends", day: $dayB, accent: context.accent, calendar: context.calendar, allowsFuture: true)
        case .weight:
            DogDayField(label: "Date", day: $dayA, accent: context.accent, calendar: context.calendar, required: true)
            text("Pounds", $lbs, "28.4", numeric: true)
        case .vet:
            text("Clinic", $name, "Dilworth Animal Hospital")
            text("Phone", $second, "704-555-0100", numeric: true)
            text("Address", $third, "Street, city")
        case .insurance:
            text("Provider", $name, "Trupanion, Lemonade, Healthy Paws…")
            text("Policy number", $second, "ABC-123456")
            text("Claims phone", $third, "800-…", numeric: true)
            let accent = context.accent
            VStack(alignment: .leading, spacing: 6) {
                Text("Insurance card").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                HStack(spacing: 12) {
                    if let cardPhoto { DogLocalThumb(name: cardPhoto, theme: theme) }
                    PhotosPicker(selection: $cardItem, matching: .images) {
                        Label(cardPhoto == nil ? "Add a photo of the card" : "Replace photo", systemImage: "creditcard")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
                Text("The card photo stays on this phone.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    private func text(_ label: String, _ binding: Binding<String>, _ placeholder: String, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(context.theme.secondaryLabel)
            WidgetUI.textField(placeholder, text: binding, theme: context.theme, numeric: numeric)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var valid: Bool {
        switch edit {
        case .vaccine, .medication: return !trimmedName.isEmpty
        case .visit: return dayA != nil || !third.trimmingCharacters(in: .whitespaces).isEmpty
        case .weight: return dayA != nil && (Double(lbs.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
        case .vet, .insurance: return true
        }
    }

    private func fill() {
        switch edit {
        case .vaccine(let v?):
            name = v.name; dayA = v.givenOn; dayB = v.dueOn; notes = v.notes
        case .visit(let v?):
            dayA = v.date; third = v.reason; second = v.clinic; notes = v.notes
        case .visit(nil):
            dayA = DogDay.string(Date(), calendar: context.calendar); second = records.vet.clinic
        case .medication(let m?):
            name = m.name; second = m.dose; third = m.schedule; dayA = m.startedOn; dayB = m.endsOn
        case .weight(let w?):
            dayA = w.date; lbs = w.lbs.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        case .weight(nil):
            dayA = DogDay.string(Date(), calendar: context.calendar)
        case .vet:
            name = records.vet.clinic; second = records.vet.phone; third = records.vet.address
        case .insurance:
            name = records.insurance.provider; second = records.insurance.policyNumber
            third = records.insurance.claimsPhone; cardPhoto = records.insurance.cardPhoto
        default:
            break
        }
    }

    private func save() {
        var r = records
        let clean = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch edit {
        case .vaccine(let v):
            let row = DogVaccine(id: v?.id ?? UUID().uuidString, name: trimmedName, givenOn: dayA, dueOn: dayB, notes: clean(notes))
            upsert(&r.vaccines, row)
        case .visit(let v):
            upsert(&r.vetVisits, DogVetVisit(id: v?.id ?? UUID().uuidString, date: dayA, clinic: clean(second), reason: clean(third), notes: clean(notes)))
        case .medication(let m):
            upsert(&r.medications, DogMedication(id: m?.id ?? UUID().uuidString, name: trimmedName, dose: clean(second),
                                                 schedule: clean(third), startedOn: dayA, endsOn: dayB))
        case .weight(let w):
            guard let day = dayA, let value = Double(lbs.replacingOccurrences(of: ",", with: ".")) else { return }
            upsert(&r.weights, DogWeight(id: w?.id ?? UUID().uuidString, date: day, lbs: value))
            r.weights.sort { $0.date < $1.date }
        case .vet:
            r.vet = DogVet(clinic: trimmedName, phone: clean(second), address: clean(third))
        case .insurance:
            if let old = records.insurance.cardPhoto, old != cardPhoto { DogLocalPhotos.delete(old) }
            r.insurance = DogInsurance(provider: trimmedName, policyNumber: clean(second), claimsPhone: clean(third), cardPhoto: cardPhoto)
        }
        context.host.haptic(.success)
        onSave(r)
        dismiss()
    }

    private func delete() {
        var r = records
        switch edit {
        case .vaccine(let v?): r.vaccines.removeAll { $0.id == v.id }
        case .visit(let v?): r.vetVisits.removeAll { $0.id == v.id }
        case .medication(let m?): r.medications.removeAll { $0.id == m.id }
        case .weight(let w?): r.weights.removeAll { $0.id == w.id }
        default: return
        }
        onSave(r)
        dismiss()
    }

    private func upsert<T: Identifiable>(_ list: inout [T], _ row: T) where T.ID == String {
        if let i = list.firstIndex(where: { $0.id == row.id }) { list[i] = row } else { list.insert(row, at: 0) }
    }
}

/// An optional calendar day ("YYYY-MM-DD"): a switch, then a date picker.
struct DogDayField: View {
    let label: String
    @Binding var day: String?
    let accent: Color
    let calendar: Calendar
    var allowsFuture = false
    var required = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !required {
                Toggle(label, isOn: Binding(
                    get: { day != nil },
                    set: { day = $0 ? (day ?? DogDay.string(Date(), calendar: calendar)) : nil }
                ))
                .tint(accent)
            }
            if day != nil {
                if allowsFuture {
                    DatePicker(required ? label : "", selection: binding, displayedComponents: .date).tint(accent)
                } else {
                    DatePicker(required ? label : "", selection: binding, in: ...Date(), displayedComponents: .date).tint(accent)
                }
            }
        }
    }

    private var binding: Binding<Date> {
        Binding(
            get: { day.flatMap { DogDay.date($0, calendar: calendar) } ?? Date() },
            set: { day = DogDay.string($0, calendar: calendar) }
        )
    }
}

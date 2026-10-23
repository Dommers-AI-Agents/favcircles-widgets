import SwiftUI
import PhotosUI
import FavWidgetsCore

/// My Dogs: each dog (opens its page), favorite dog spots, reminders.
struct MyDogsView: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    @ObservedObject var state: WidgetStateController<DogsState>
    let onAddDog: () -> Void
    let onOpenPost: (DogPost) -> Void
    @State private var openDog: DogProfile?
    @State private var documentsFor: DogProfile?
    @State private var addingPlace = false
    @State private var leaving = false

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(store.me.dogs) { dog in
                    dogRow(dog, theme: theme)
                }
                Button(action: onAddDog) {
                    Label(store.me.dogs.isEmpty ? "Add your dog" : "Add another dog", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(context.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }
                .buttonStyle(.plain)

                places(theme)

                Toggle(isOn: Binding(get: { state.model.remindersOn }, set: { on in state.update { $0.remindersOn = on } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminders").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text("Vaccines due (a month and a week before), birthdays and gotcha days. On this phone.")
                            .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                .tint(context.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))

                Button { leaving = true } label: {
                    Text("Leave the Dog Park").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .fullScreenCoverOrSheet(item: $openDog) { dog in
            DogPageView(context: context, store: store, state: state, dogId: dog.id, onClose: { openDog = nil })
        }
        .sheet(item: $documentsFor) { dog in
            DogDocumentsSheet(context: context, state: state, dog: dog)
        }
        .sheet(isPresented: $addingPlace) {
            DogPlacePicker(context: context) { place in
                state.update { s in
                    // Picked again: one row, moved to the top
                    s.places.removeAll { $0.placeId != nil && $0.placeId == place.placeId }
                    s.places.insert(place, at: 0)
                }
            }
        }
        .confirmationDialog("Leave the Dog Park?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your posts come down and the Daily Dog stops. Your dogs' records stay here, private.")
        }
    }

    private func dogRow(_ dog: DogProfile, theme: WidgetTheme) -> some View {
        let records = state.model.records(for: dog.id)
        let attention = records.vaccines.filter { DogVaccineStatus.of($0, calendar: context.calendar).needsAttention }
        return HStack(spacing: 10) {
            Button { openDog = dog } label: {
                HStack(spacing: 14) {
                    DogAvatar(url: dog.photoURL, size: 64, accent: context.accent, theme: theme)
                    dogSummary(dog, records: records, attention: attention, theme: theme)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            documentsButton(dog, count: records.documents.count, theme: theme)
            Button { openDog = dog } label: {
                Image(systemName: "chevron.right").foregroundStyle(theme.secondaryLabel).frame(width: 20, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.secondaryBackground))
    }

    /// The dog's paperwork in one tap, without opening its page
    private func documentsButton(_ dog: DogProfile, count: Int, theme: WidgetTheme) -> some View {
        Button { documentsFor = dog } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "doc.text.fill").font(.system(size: 19, weight: .semibold)).foregroundStyle(context.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(context.accent.opacity(0.16)))
                if count > 0 {
                    Text("\(count)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(context.accent))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dog.name)'s documents")
    }

    private func dogSummary(_ dog: DogProfile, records: DogRecords, attention: [DogVaccine], theme: WidgetTheme) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(dog.name).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
                let sub = DogCopy.subtitle(dog, calendar: context.calendar)
                if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                if !dog.personality.isEmpty {
                    Text(dog.personality).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.label).lineLimit(1)
                }
                if let first = attention.first {
                    Label("\(first.name): \(DogVaccineStatus.of(first, calendar: context.calendar).text)", systemImage: "syringe")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.warning)
                }
            }
    }

    private func places(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header("Favorite dog spots", theme: theme)
                Button { addingPlace = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
            }
            if state.model.places.isEmpty {
                Text("Dog parks, patios that welcome pups, the pet store with the treat jar. They go on your map in a \"Dog spots\" circle.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(state.model.places) { place in
                Button {
                    if let id = place.placeId {
                        context.host.openPlace(WidgetPlaceRef(id: id, name: place.name))
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("📍").font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                            if let address = place.address, !address.isEmpty {
                                Text(address).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove from this list", role: .destructive) {
                        state.update { $0.places.removeAll { $0.id == place.id } }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private func leave() {
        Task { @MainActor in
            do {
                try await DogsClient(context: context).leave()
                store.setMember(false)
                await store.refresh(context, force: true)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't leave", message: DogErrors.message(error)))
            }
        }
    }
}

/// Add or edit a dog: photo, name, breed, birthday, gotcha day, personality.
struct DogEditSheet: View {
    let context: WidgetContext
    let dog: DogProfile?
    let onSaved: (DogProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var breed = ""
    @State private var personality = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var hasGotcha = false
    @State private var gotcha = Date()
    @State private var item: PhotosPickerItem?
    @State private var photo: PostcardPlatformImage?
    @State private var busy = false

    var body: some View {
        let theme = context.theme
        let valid = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let accent = context.accent
        WidgetSheet(title: dog == nil ? "Add your dog" : "Edit \(dog?.name ?? "")", theme: theme,
                    confirm: (label: busy ? "Saving…" : "Save", enabled: valid && !busy, action: save), cancelDisabled: busy) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PhotosPicker(selection: $item, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let photo {
                                Image(postcardImage: photo).resizable().scaledToFill().frame(width: 130, height: 130).clipShape(Circle())
                            } else {
                                DogAvatar(url: dog?.photoURL, size: 130, accent: accent, theme: theme)
                            }
                            Image(systemName: "camera.circle.fill").font(.system(size: 34)).foregroundStyle(accent)
                                .background(Circle().fill(theme.background))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    field("Name", text: $name, placeholder: "Biscuit")
                    field("Breed", text: $breed, placeholder: "Corgi, mutt, mystery floof…")
                    field("Personality", text: $personality, placeholder: "Professional sock thief")
                    Toggle("Birthday", isOn: $hasBirthday).tint(context.accent)
                    if hasBirthday {
                        DatePicker("Born", selection: $birthday, in: ...Date(), displayedComponents: .date).tint(context.accent)
                    }
                    Toggle("Gotcha day (the day they came home)", isOn: $hasGotcha).tint(context.accent)
                    if hasGotcha {
                        DatePicker("Came home", selection: $gotcha, in: ...Date(), displayedComponents: .date).tint(context.accent)
                    }
                    Text("Name, photo, breed, age and personality show in the Dog Park. Health records never do.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                .padding(16)
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear(perform: fill)
        .onChange(of: item) { picked in
            guard let picked else { return }
            Task { @MainActor in
                if let data = try? await picked.loadTransferable(type: Data.self) { photo = PostcardPlatformImage(data: data) }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(context.theme.secondaryLabel)
            WidgetUI.textField(placeholder, text: text, theme: context.theme)
        }
    }

    private func fill() {
        guard let dog else { return }
        name = dog.name; breed = dog.breed; personality = dog.personality
        if let b = dog.birthday, let d = DogDay.date(b, calendar: context.calendar) { hasBirthday = true; birthday = d }
        if let g = dog.gotchaDay, let d = DogDay.date(g, calendar: context.calendar) { hasGotcha = true; gotcha = d }
    }

    private func save() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                var draft = dog ?? DogProfile(id: "", name: "")
                draft.name = name.trimmingCharacters(in: .whitespaces)
                draft.breed = breed.trimmingCharacters(in: .whitespaces)
                draft.personality = personality.trimmingCharacters(in: .whitespaces)
                draft.birthday = hasBirthday ? DogDay.string(birthday, calendar: context.calendar) : nil
                draft.gotchaDay = hasGotcha ? DogDay.string(gotcha, calendar: context.calendar) : nil
                if let photo, let jpeg = EventImagePrep.jpeg(photo) {
                    draft.photoUrl = try await context.host.uploadImage(jpeg).absoluteString
                }
                let client = DogsClient(context: context)
                let saved = dog == nil ? try await client.createDog(draft) : try await client.updateDog(draft)
                context.host.haptic(.success)
                context.track(dog == nil ? "dog_added" : "dog_edited")
                dismiss()
                onSaved(saved)
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save", message: DogErrors.message(error)))
            }
        }
    }
}

/// Search for a dog spot and save it to the "Dog spots" circle. Results come
/// as you type: your own saves first, then Apple Maps. The save goes through
/// the same server save as Add Place (Google's details, no duplicates).
struct DogPlacePicker: View {
    let context: WidgetContext
    let onSaved: (DogFavoritePlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WidgetPlaceCandidate] = []
    @State private var searching = false
    @State private var saving: String?
    @State private var near: WidgetCoordinate?
    @State private var mySaves: [WidgetPlaceCandidate] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let theme = context.theme
        WidgetSheet(title: "Add a dog spot", theme: theme) {
            VStack(spacing: 0) {
                WidgetUI.textField("Dog park, patio, pet store…", text: $query, theme: theme)
                    .padding(16)
                    .onSubmit { search(after: 0) }
                    .onChange(of: query) { _ in search(after: 300) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if searching && results.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.top, 20) }
                        if results.isEmpty, !searching, query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ForEach(["Dog park", "Dog friendly patio", "Pet store", "Groomer"], id: \.self) { s in
                                Button { query = s } label: {
                                    Label(s, systemImage: "magnifyingglass").font(.system(size: 15)).foregroundStyle(context.accent)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                        ForEach(results) { place in
                            Button { save(place) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                                        if let address = place.address { Text(address).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1) }
                                        if place.isGlobal {
                                            Label("On your map", systemImage: "mappin.circle.fill")
                                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(context.accent)
                                        }
                                    }
                                    Spacer()
                                    if saving == place.id { ProgressView() } else { Image(systemName: "plus.circle").foregroundStyle(context.accent) }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                            }
                            .buttonStyle(.plain)
                            .disabled(saving != nil)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task {
            near = await context.host.currentLocation()
            mySaves = (try? await context.host.fetchPlaces(WidgetPlaceQuery(sources: [.mine], near: near, radiusMeters: 200_000))) ?? []
            if !query.isEmpty { search(after: 0) }
        }
        .onDisappear { searchTask?.cancel() }
    }

    /// Your matching saves show at once; Apple Maps follows after a short pause.
    private func search(after delayMs: UInt64) {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; searching = false; return }
        results = DogSpotSearch.merge(saves: mySaves, apple: results.filter { !$0.isGlobal }, query: text)
        searching = true
        searchTask = Task { @MainActor in
            if delayMs > 0 { try? await Task.sleep(nanoseconds: delayMs * 1_000_000) }
            guard !Task.isCancelled else { return }
            let apple = (try? await context.host.searchPlaces(text, near: near)) ?? []
            guard !Task.isCancelled else { return }
            results = DogSpotSearch.merge(saves: mySaves, apple: apple, query: text)
            searching = false
        }
    }

    private func save(_ place: WidgetPlaceCandidate) {
        saving = place.id
        Task { @MainActor in
            defer { saving = nil }
            do {
                let saved = try await DogsClient(context: context).savePlace(place)
                context.host.haptic(.success)
                context.track("dog_spot_saved")
                dismiss()
                onSaved(DogFavoritePlace(name: place.name, address: place.address, placeId: saved.placeId ?? (place.isGlobal ? place.id : nil)))
                if saved.alreadySaved == true, let circle = saved.circleName, circle != "Dog spots" {
                    context.host.presentAlert(WidgetAlert(
                        title: "Already on your map",
                        message: "\(place.name) is saved in your \(circle) circle, so it's linked here instead of saved twice."))
                }
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save the spot", message: DogErrors.message(error)))
            }
        }
    }
}

import SwiftUI
import PhotosUI
import FavWidgetsCore

/// A small photo of the exercise (the machine's placard), or a symbol
/// when the person hasn't attached one.
struct ExerciseThumb: View {
    let url: URL?
    let symbolName: String
    let accent: Color
    let theme: WidgetTheme
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.12))
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Image(systemName: symbolName).foregroundStyle(accent) }
                }
            } else {
                Image(systemName: symbolName).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Attach or replace an exercise's photo: snap the machine's placard or
/// pick from the library. Uploaded through the app's image pipeline (a
/// thumbnail, so the compressing path is the right one).
struct ExercisePhotoSheet: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let exerciseId: String
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var picked: PostcardPlatformImage?
    @State private var uploading = false

    private var theme: WidgetTheme { context.theme }
    private var name: String { settings.model.exercise(id: exerciseId)?.name ?? "Exercise" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let picked {
                    Image(postcardImage: picked).resizable().scaledToFit().frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if let url = settings.model.imageURL(for: exerciseId) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFit() } else { Color.clear }
                    }
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("Snap the machine's placard or the setup you use, so it's right there next time.")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photo library", systemImage: "photo.on.rectangle").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(context.accent).frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    if PostcardCameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            Label("Camera", systemImage: "camera.fill").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(context.accent).frame(maxWidth: .infinity).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }
                if picked != nil {
                    WidgetUI.primaryButton(uploading ? "Saving…" : "Use this photo", color: context.accent) { save() }
                        .disabled(uploading)
                }
                if settings.model.imageURL(for: exerciseId) != nil && picked == nil {
                    Button("Remove photo") {
                        settings.update { $0.exerciseImages.removeValue(forKey: exerciseId) }
                        dismiss()
                    }
                    .font(.system(size: 14)).foregroundStyle(theme.danger)
                }
                Spacer()
            }
            .padding(16)
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle(name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = PostcardPlatformImage(data: data) {
                        picked = image
                    }
                }
            }
            .widgetCameraCover(isPresented: $showCamera) {
                #if os(iOS)
                PostcardCameraPicker(image: $picked).ignoresSafeArea()
                #endif
            }
        }
    }

    private func save() {
        guard let picked, !uploading else { return }
        uploading = true
        Task {
            defer { uploading = false }
            do {
                #if os(iOS)
                guard let jpeg = picked.jpegData(compressionQuality: 0.8) else { return }
                #else
                let jpeg = Data()
                #endif
                let url = try await context.host.uploadImage(jpeg)
                settings.update { $0.exerciseImages[exerciseId] = url.absoluteString }
                context.track("exercise_photo_added")
                context.host.haptic(.success)
                dismiss()
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't save the photo", message: error.localizedDescription))
            }
        }
    }
}

/// One cardio entry in the active session: machine, minutes, distance,
/// effort, calories (typed or estimated), done.
struct CardioRowView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let entryId: UUID
    let onCompleted: () -> Void

    @State private var minutesText = ""
    @State private var distanceText = ""
    @State private var caloriesText = ""

    private var theme: WidgetTheme { context.theme }
    private var entry: CardioEntry? { settings.model.activeSession?.cardio.first { $0.id == entryId } }
    private var isDone: Bool { entry?.completedAt != nil }

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: entry.kind.symbolName).font(.system(size: 18, weight: .semibold)).foregroundStyle(context.accent).frame(width: 28)
                    Text(entry.kind.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
                    Spacer()
                    Picker("Effort", selection: Binding(get: { entry.intensity }, set: { v in mutate { $0.intensity = v } })) {
                        ForEach(CardioIntensity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.secondaryLabel)
                }
                HStack(spacing: 8) {
                    field("min", text: $minutesText, width: 64)
                    if entry.kind.tracksDistance { field(settings.model.distanceUnit, text: $distanceText, width: 72, decimal: true) }
                    field("kcal", text: $caloriesText, width: 72)
                    if entry.calories == nil, let est = WorkoutCardioLogic.calories(for: entry, weightKg: settings.model.profile.weightKg) {
                        Text("≈\(est)").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    } else if entry.calories == nil && settings.model.profile.weightKg == nil {
                        Text("add weight in settings for an estimate").font(.system(size: 10)).foregroundStyle(theme.secondaryLabel).lineLimit(2)
                    }
                    Spacer()
                    Button(action: toggleDone) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isDone ? .white : theme.secondaryLabel)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isDone ? theme.success : theme.tertiaryBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .opacity(isDone ? 0.75 : 1)
            .onAppear(perform: seed)
            .onChange(of: minutesText) { t in if let v = WorkoutFormat.parseInt(t) ?? (t.isEmpty ? 0 : nil) { mutate { $0.minutes = v } } }
            .onChange(of: distanceText) { t in if let v = WorkoutFormat.parseDecimal(t) ?? (t.isEmpty ? 0 : nil) { mutate { $0.distance = v > 0 ? v : nil } } }
            .onChange(of: caloriesText) { t in if let v = WorkoutFormat.parseInt(t) ?? (t.isEmpty ? 0 : nil) { mutate { $0.calories = v > 0 ? v : nil } } }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, width: CGFloat, decimal: Bool = false) -> some View {
        VStack(spacing: 2) {
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .modifier(NumericKeyboard(decimal: decimal))
            Text(placeholder).font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private func seed() {
        guard let entry else { return }
        minutesText = entry.minutes == 0 ? "" : String(entry.minutes)
        distanceText = entry.distance.map { WorkoutFormat.decimalText($0) } ?? ""
        caloriesText = entry.calories.map(String.init) ?? ""
    }

    private func mutate(_ change: (inout CardioEntry) -> Void) {
        settings.update { model in
            guard let index = model.activeSession?.cardio.firstIndex(where: { $0.id == entryId }) else { return }
            change(&model.activeSession!.cardio[index])
        }
    }

    private func toggleDone() {
        let completing = !isDone
        mutate { $0.completedAt = completing ? Date() : nil }
        if completing { onCompleted() }
    }
}

private struct NumericKeyboard: ViewModifier {
    let decimal: Bool
    func body(content: Content) -> some View {
        if decimal { content.widgetDecimalKeyboard() } else { content.widgetNumberKeyboard() }
    }
}

/// The finished workout, drawn as a card for the share sheet.
struct WorkoutShareCard: View {
    let summary: WorkoutShareSummary
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(summary.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "dumbbell.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 14) {
                stat("\(max(1, summary.durationSeconds / 60))", "min")
                if !summary.exercises.isEmpty { stat("\(summary.exercises.count)", "exercises"); stat("\(summary.completedSets)", "sets") }
                if summary.cardioMinutes > 0 { stat("\(summary.cardioMinutes)", "min cardio") }
                if summary.prCount > 0 { stat("\(summary.prCount)", "PR\(summary.prCount == 1 ? "" : "s")") }
            }
            ForEach(Array(summary.exercises.prefix(6).enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text(line.bestSet + (line.isPR ? " 🏆" : "")).font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                }
            }
            ForEach(Array(summary.cardio.prefix(3).enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text(line.detail).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                }
            }
            Spacer(minLength: 4)
            Text("FavCircles").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(22)
        .frame(width: 400, alignment: .leading)
        .background(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
        }
    }

    @MainActor
    static func jpeg(summary: WorkoutShareSummary, accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: WorkoutShareCard(summary: summary, accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}

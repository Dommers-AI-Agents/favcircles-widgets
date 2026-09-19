import SwiftUI
import PhotosUI
import FavWidgetsCore

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

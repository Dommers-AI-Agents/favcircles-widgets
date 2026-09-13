import SwiftUI
#if os(iOS)
import UIKit

/// The system camera, for "Take photo". Presented in a sheet; the captured
/// image lands in the binding and the sheet dismisses itself.
struct PostcardCameraPicker: UIViewControllerRepresentable {
    @Binding var image: PostcardPlatformImage?
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: PostcardCameraPicker

        init(_ parent: PostcardCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let picked = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            parent.image = picked
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

extension View {
    /// The camera must be presented full-screen on iPhone (a page sheet can
    /// render the preview black/offset); macOS has no fullScreenCover.
    @ViewBuilder
    func widgetCameraCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

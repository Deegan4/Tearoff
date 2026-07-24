import SwiftUI
import UIKit

/// A plain manual-shutter camera. Unlike VisionKit's document scanner it
/// never auto-captures — the photo is taken only when the user taps the
/// shutter. Editing is off so we keep the **full-resolution** capture: the
/// system's edited/cropped image is downscaled to a few hundred pixels, which
/// starves OCR, whereas the original is the full sensor photo (~12 MP).
struct ReceiptCamera: UIViewControllerRepresentable {
    /// Called with the captured image, or nil on cancel.
    var onCapture: (UIImage?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        // Highest-quality capture the device offers.
        picker.cameraCaptureMode = .photo
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Full-resolution original (editing is disabled).
            let image = (info[.originalImage] as? UIImage) ?? (info[.editedImage] as? UIImage)
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

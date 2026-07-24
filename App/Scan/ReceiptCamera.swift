import SwiftUI
import VisionKit
import UIKit

/// The receipt scanner, backed by VisionKit's document camera. It finds the
/// receipt's edges, captures at high resolution, and perspective-corrects
/// (deskews) the page — so OCR sees a flat, cropped, sharp receipt instead of
/// a phone-angle photo of one. The user reviews and can retake before keeping
/// the shot. We use the first scanned page.
struct ReceiptCamera: UIViewControllerRepresentable {
    /// Called with the captured, deskewed page image, or nil on cancel/failure.
    var onCapture: (UIImage?) -> Void

    /// True on any device with a camera (iOS 13+). False in the simulator.
    static var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // First page is the receipt; each page is already deskewed + cropped.
            let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            onCapture(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCapture(nil)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCapture(nil)
        }
    }
}

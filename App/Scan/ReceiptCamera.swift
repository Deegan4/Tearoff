import SwiftUI
import VisionKit
import UIKit

/// The receipt scanner, backed by VisionKit's document camera. It finds the
/// receipt's edges, captures at high resolution, and perspective-corrects
/// (deskews) the page — so OCR sees a flat, cropped, sharp receipt instead of
/// a phone-angle photo of one. The user reviews and can retake before keeping
/// the shot. Multiple scanned pages (a long receipt shot in sections) are
/// stitched top-to-bottom into one image so OCR and storage see the whole thing.
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
            guard scan.pageCount > 0 else { onCapture(nil); return }
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onCapture(pages.count == 1 ? pages[0] : Self.stitchVertically(pages))
        }

        /// Stack pages top-to-bottom into one image. Each page is scaled to a
        /// shared width (bounded, to keep memory sane) so a long receipt shot in
        /// sections reads as a single continuous slip.
        static func stitchVertically(_ pages: [UIImage], maxWidth: CGFloat = 1600, gap: CGFloat = 16) -> UIImage {
            let width = min(maxWidth, pages.map(\.size.width).max() ?? maxWidth)
            // Height each page occupies at the shared width, preserving aspect.
            let scaledHeights = pages.map { page -> CGFloat in
                let scale = width / max(page.size.width, 1)
                return page.size.height * scale
            }
            let totalHeight = scaledHeights.reduce(0, +) + gap * CGFloat(max(pages.count - 1, 0))

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1   // width is already in the pixel budget we want
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: width, height: totalHeight), format: format)
            return renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
                var y: CGFloat = 0
                for (page, height) in zip(pages, scaledHeights) {
                    page.draw(in: CGRect(x: 0, y: y, width: width, height: height))
                    y += height + gap
                }
            }
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

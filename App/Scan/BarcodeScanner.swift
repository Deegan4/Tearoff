import SwiftUI
import VisionKit

/// Live barcode scanner over the camera. Recognizes the common retail
/// symbologies and calls back with the first payload it reads, hands-free.
struct BarcodeScanner: UIViewControllerRepresentable {
    /// Called with the decoded barcode string.
    var onScan: (String) -> Void

    /// Whether this device can run the data scanner (false on Simulator and
    /// unsupported hardware, so callers can hide the entry point).
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliver(item)
        }

        func dataScanner(
            _ scanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            addedItems.forEach(deliver)
        }

        /// Fire once, for the first barcode with a readable payload.
        private func deliver(_ item: RecognizedItem) {
            guard !handled, case let .barcode(barcode) = item,
                  let value = barcode.payloadStringValue, !value.isEmpty else { return }
            handled = true
            onScan(value)
        }
    }
}

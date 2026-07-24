import SwiftUI
import UIKit

/// Minimal UIActivityViewController wrapper. A file URL wrapped as Identifiable
/// so it can drive `.sheet(item:)` and hand the exported CSV to the system
/// share sheet (AirDrop, Files, Mail, …).
struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

import Foundation
import Observation
import VaultCore

/// On-device store of scan-accuracy telemetry. Aggregates counts only — never
/// receipt contents — into a single `AccuracyLedger` persisted as JSON in
/// Application Support. Local by design: nothing leaves the device, and the
/// user can clear it. Drives the Settings dashboard and, later, `@Guide`
/// tuning priorities.
@MainActor
@Observable
final class ExtractionTelemetryStore {
    static let shared = ExtractionTelemetryStore()

    private(set) var ledger: AccuracyLedger

    /// Non-observed so writes don't churn the view graph.
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AccuracyLedger.self, from: data) {
            self.ledger = decoded
        } else {
            self.ledger = AccuracyLedger()
        }
    }

    /// Fold one confirmed scan into the aggregate and persist. `parsed` is what
    /// the scanner produced; `saved` is what the user kept.
    func record(parsed: ExtractionSnapshot, saved: ExtractionSnapshot) {
        let result = ExtractionAudit.compare(parsed: parsed, saved: saved)
        ledger.record(result)
        persist()
    }

    /// Wipe all telemetry. Offered in Settings so the aggregate is the user's
    /// to clear.
    func reset() {
        ledger = AccuracyLedger()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        return base.appending(path: "extraction-telemetry.json")
    }
}

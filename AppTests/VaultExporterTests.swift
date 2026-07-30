import Testing
import Foundation
@testable import Tearoff
import VaultCore

/// Tests for the export bridge - the App-side half of a Pro feature that had
/// no coverage at all. `writeCSV`/`writePDFReport` return `nil` on a write
/// failure, and a caller that ignored that shipped a button which silently did
/// nothing, so the contract these pin is "a URL you can actually read back".
@MainActor
struct VaultExporterTests {

    private func purchase(
        _ merchant: String,
        _ cents: Int,
        daysAgo: Int = 0,
        category: PurchaseCategory = .electronics
    ) -> StoredPurchase {
        StoredPurchase(
            merchant: merchant,
            purchaseDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            totalCents: Cents(cents),
            category: category
        )
    }

    // MARK: Row mapping

    @Test("Rows come back newest purchase first")
    func rowsAreNewestFirst() {
        let rows = VaultExporter.rows(from: [
            purchase("Older", 1000, daysAgo: 30),
            purchase("Newer", 2000, daysAgo: 1)
        ])
        #expect(rows.map(\.merchant) == ["Newer", "Older"])
    }

    @Test("Money crosses the boundary as integer minor units")
    func moneyStaysInCents() {
        let rows = VaultExporter.rows(from: [purchase("Best Buy", 129_99)])
        // Never a Double - a rounded 129.99 is a support ticket.
        #expect(rows.first?.totalCents == 129_99)
    }

    @Test("An empty vault maps to no rows rather than failing")
    func emptyVaultMapsToNoRows() {
        #expect(VaultExporter.rows(from: []).isEmpty)
    }

    // MARK: CSV

    @Test("CSV export writes a file that reads back with a row per purchase")
    func csvWritesReadableFile() throws {
        let url = try #require(VaultExporter.writeCSV([
            purchase("Best Buy", 129_99),
            purchase("Target", 45_00, daysAgo: 5)
        ]))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("Best Buy"))
        #expect(text.contains("Target"))
        // Header plus one line per purchase, ignoring the trailing newline.
        // Split on the newline *property*, not the character "\n": the export
        // is RFC 4180 CRLF, and Swift treats "\r\n" as one grapheme cluster,
        // so splitting on "\n" matches nothing and yields a single line.
        let lines = text.split(whereSeparator: \.isNewline)
        #expect(lines.count == 3)
    }

    @Test("Re-exporting overwrites rather than appending")
    func csvExportIsIdempotent() throws {
        _ = VaultExporter.writeCSV([purchase("First", 100), purchase("Second", 200)])
        let url = try #require(VaultExporter.writeCSV([purchase("Only", 100)]))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("First"))
        #expect(text.contains("Only"))
    }

    @Test("An empty vault still produces a CSV rather than nil")
    func csvHandlesEmptyVault() throws {
        let url = try #require(VaultExporter.writeCSV([]))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: PDF

    @Test("PDF export writes a non-empty file")
    func pdfWritesNonEmptyFile() throws {
        let url = try #require(VaultExporter.writePDFReport([purchase("Best Buy", 129_99)]))
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
        // %PDF- magic, so a truncated or empty write fails here rather than in
        // the share sheet.
        #expect(data.prefix(5) == Data("%PDF-".utf8))
    }
}

import Foundation
import VaultCore

/// Bridges stored records to VaultCore's pure exporter and writes the result
/// to a temporary file for sharing. Resolves each purchase's return/warranty
/// deadlines through ResolverStore so the export carries concrete dates, not
/// raw window inputs.
@MainActor
enum VaultExporter {
    /// Build the exportable rows, newest purchase first.
    static func rows(from purchases: [StoredPurchase]) -> [ExportablePurchase] {
        purchases
            .sorted { $0.purchaseDate > $1.purchaseDate }
            .map { p in
                ExportablePurchase(
                    merchant: p.merchant,
                    purchaseDate: p.purchaseDate,
                    category: p.category.displayName,
                    totalCents: p.totalCents.raw,
                    status: p.status.label,
                    returnDeadline: ResolverStore.shared.returnWindow(for: p)?.deadline,
                    warrantyDeadline: ResolverStore.shared.warrantyWindow(for: p)?.deadline,
                    orderNumber: p.orderNumber,
                    paymentMethod: p.paymentMethod,
                    note: p.note
                )
            }
    }

    /// Write a CSV of the vault to a temp file and return its URL, or nil on
    /// a write failure. The filename is stable per export session.
    static func writeCSV(_ purchases: [StoredPurchase]) -> URL? {
        let csv = VaultExport.csv(rows(from: purchases))
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Tearoff-Vault.csv")
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

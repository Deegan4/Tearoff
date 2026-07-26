import Foundation
import UIKit
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

    /// Pro feature: a one-page PDF year-in-review — spend by category, open
    /// vs. resolved counts, and the year's purchases with their resolved
    /// deadlines. Only `purchases` dated within the last 365 days count.
    /// Needs UIKit (PDFKit rendering), so this stays in the App layer even
    /// though the numbers themselves come from VaultCore's pure aggregator.
    static func writePDFReport(_ allPurchases: [StoredPurchase], now: Date = Date()) -> URL? {
        let yearAgo = Calendar.utcGregorian.date(byAdding: .day, value: -365, to: now) ?? now
        let purchases = allPurchases
            .filter { $0.purchaseDate >= yearAgo }
            .sorted { $0.purchaseDate > $1.purchaseDate }

        let inputs = purchases.map { p in
            InsightsInput(
                category: p.category.displayName,
                totalCents: p.totalCents.raw,
                isActive: !p.status.isResolved,
                returnDeadline: ResolverStore.shared.returnWindow(for: p)?.deadline,
                warrantyDeadline: ResolverStore.shared.warrantyWindow(for: p)?.deadline
            )
        }
        let summary = VaultInsights.summary(inputs, now: now)

        let pageWidth: CGFloat = 612, pageHeight: CGFloat = 792   // US Letter, points
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 6) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let rect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: .greatestFiniteMagnitude)
                let bounding = (text as NSString).boundingRect(
                    with: rect.size, options: [.usesLineFragmentOrigin],
                    attributes: attrs, context: nil)
                if y + bounding.height > pageHeight - margin {
                    context.beginPage()
                    y = margin
                }
                (text as NSString).draw(in: CGRect(x: margin, y: y, width: rect.width, height: bounding.height), withAttributes: attrs)
                y += bounding.height + spacing
            }

            draw("Tearoff — Year in Review", font: .boldSystemFont(ofSize: 22), spacing: 4)
            draw("Generated \(now.formatted(date: .abbreviated, time: .omitted))",
                 font: .systemFont(ofSize: 11), color: .darkGray, spacing: 20)

            draw("Summary", font: .boldSystemFont(ofSize: 15), spacing: 8)
            draw("Total tracked: \(Cents(summary.totalTrackedCents).formatted(currencyCode: "USD")) across \(summary.purchaseCount) purchases",
                 font: .systemFont(ofSize: 12))
            draw("Open returns: \(summary.openReturnCount), worth \(Cents(summary.openReturnValueCents).formatted(currencyCode: "USD"))",
                 font: .systemFont(ofSize: 12))
            draw("Active warranties: \(summary.activeWarrantyCount) (\(summary.warrantiesExpiringSoonCount) expiring within 30 days)",
                 font: .systemFont(ofSize: 12), spacing: 20)

            draw("Spend by category", font: .boldSystemFont(ofSize: 15), spacing: 8)
            if summary.topCategories.isEmpty {
                draw("No purchases this year.", font: .systemFont(ofSize: 12), color: .darkGray, spacing: 20)
            } else {
                for c in summary.topCategories {
                    draw("\(c.category): \(Cents(c.totalCents).formatted(currencyCode: "USD")) (\(c.count))",
                         font: .systemFont(ofSize: 12))
                }
                y += 14
            }

            draw("Purchases", font: .boldSystemFont(ofSize: 15), spacing: 8)
            if purchases.isEmpty {
                draw("None in the last year.", font: .systemFont(ofSize: 12), color: .darkGray)
            } else {
                for p in purchases {
                    let deadline = ResolverStore.shared.returnWindow(for: p)?.deadline
                        ?? ResolverStore.shared.warrantyWindow(for: p)?.deadline
                    let deadlineText = deadline.map { " — through \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
                    draw("\(p.purchaseDate.formatted(date: .numeric, time: .omitted))  \(p.merchant) — \(p.totalCents.formatted(currencyCode: "USD")) (\(p.status.label))\(deadlineText)",
                         font: .systemFont(ofSize: 11), spacing: 4)
                }
            }
        }

        let url = FileManager.default.temporaryDirectory.appending(path: "Tearoff-Year-in-Review.pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

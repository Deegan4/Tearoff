import SwiftUI
import VaultCore

struct PurchaseDetailView: View {
    let purchase: StoredPurchase
    @State private var showReceipt = false

    var body: some View {
        Form {
            Section("Purchase") {
                LabeledContent("Merchant", value: purchase.merchant)
                LabeledContent("Date", value: purchase.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Total", value: purchase.totalCents.formatted(currencyCode: "USD"))
                LabeledContent("Category", value: purchase.category.displayName)
            }

            if let window = ResolverStore.shared.returnWindow(for: purchase) {
                Section("Return window") {
                    LabeledContent("Return by", value: window.deadline.formatted(date: .abbreviated, time: .omitted))
                    Text(window.provenance.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let warranty = ResolverStore.shared.warrantyWindow(for: purchase) {
                Section("Warranty") {
                    LabeledContent("Covered until", value: warranty.deadline.formatted(date: .abbreviated, time: .omitted))
                    Text(warranty.provenance.isEstimate
                         ? "Estimate — \(warranty.provenance.explanation)"
                         : warranty.provenance.explanation)
                        .font(.caption)
                        .foregroundStyle(warranty.provenance.isEstimate ? .orange : .secondary)
                }
            }

            if !purchase.note.isEmpty {
                Section("Note") { Text(purchase.note) }
            }
        }
        .navigationTitle(purchase.merchant)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Receipt", systemImage: "printer") { showReceipt = true }
            }
        }
        .fullScreenCover(isPresented: $showReceipt) {
            ReceiptPrintView(purchase: purchase) { showReceipt = false }
        }
    }
}

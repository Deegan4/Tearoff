import SwiftUI
import SwiftData
import VaultCore

struct PurchaseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let purchase: StoredPurchase
    @State private var showReceipt = false
    @State private var isEditing = false
    @State private var confirmDelete = false

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

            Section {
                Button("Delete Purchase", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle(purchase.merchant)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Receipt", systemImage: "printer") { showReceipt = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            AddPurchaseView(editing: purchase)
        }
        .fullScreenCover(isPresented: $showReceipt) {
            ReceiptPrintView(purchase: purchase) { showReceipt = false }
        }
        .confirmationDialog("Delete this purchase?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deletePurchase)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the record and cancels its alerts.")
        }
    }

    private func deletePurchase() {
        let id = purchase.id
        Task { await NotificationScheduler.shared.cancel(purchaseID: id) }
        context.delete(purchase)
        dismiss()
    }
}

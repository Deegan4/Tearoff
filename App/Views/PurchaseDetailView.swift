import SwiftUI
import SwiftData
import UIKit
import VaultCore

struct PurchaseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let purchase: StoredPurchase
    @State private var showReceipt = false
    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var showScanImage = false

    var body: some View {
        Form {
            Section("Purchase") {
                LabeledContent("Merchant", value: purchase.merchant)
                LabeledContent("Date", value: purchase.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Total", value: purchase.totalCents.formatted(currencyCode: "USD"))
                LabeledContent("Category", value: purchase.category.displayName)
            }
            .staggeredAppear(0)

            if let window = ResolverStore.shared.returnWindow(for: purchase) {
                Section("Return window") {
                    LabeledContent("Return by") {
                        HStack(spacing: 6) {
                            // A pulsing urgency cue when the window is closing.
                            if (0...3).contains(window.daysRemaining(asOf: .now)) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.red)
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                            Text(window.deadline.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    Text(window.provenance.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .staggeredAppear(1)
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
                .staggeredAppear(2)
            }

            if !purchase.note.isEmpty {
                Section("Note") { Text(purchase.note) }
                    .staggeredAppear(3)
            }

            if let data = purchase.receiptImageData, let image = UIImage(data: data) {
                Section("Scanned receipt") {
                    Button {
                        showScanImage = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 260)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scanned receipt, tap to enlarge")
                }
                .staggeredAppear(4)
            }

            Section {
                Button("Delete Purchase", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
            }
            .staggeredAppear(5)
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
        .fullScreenCover(isPresented: $showScanImage) {
            if let data = purchase.receiptImageData, let image = UIImage(data: data) {
                ReceiptImageViewer(image: image) { showScanImage = false }
            }
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

/// Full-screen, pinch-to-zoom viewer for the stored receipt image.
private struct ReceiptImageViewer: View {
    let image: UIImage
    var onDone: () -> Void

    // `zoom` is the live scale; `committed` is the scale settled after the
    // last gesture, so successive pinches accumulate instead of resetting.
    @State private var zoom: CGFloat = 1
    @State private var committed: CGFloat = 1

    private let range: ClosedRange<CGFloat> = 1...4

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { zoom = clamp(committed * $0.magnification) }
                            .onEnded { _ in committed = zoom }
                    )
                    // Double-tap toggles between fit and 2×, and gives an
                    // always-available way back to fit when zoomed in.
                    .onTapGesture(count: 2) {
                        withAnimation(.spring) {
                            zoom = zoom > 1 ? 1 : 2
                            committed = zoom
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

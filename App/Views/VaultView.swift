import SwiftUI
import SwiftData
import UIKit
import VaultCore

struct VaultView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredPurchase.purchaseDate, order: .reverse)
    private var purchases: [StoredPurchase]

    @State private var selection: StoredPurchase?
    @State private var isAdding = false
    @State private var isScanning = false
    @State private var isReadingReceipt = false
    @State private var draft: ScanDraft?
    @State private var scanError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(purchases) { purchase in
                    NavigationLink(value: purchase) {
                        PurchaseRow(
                            purchase: purchase,
                            returnWindow: ResolverStore.shared.returnWindow(for: purchase)
                        )
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Vault")
            .overlay {
                if purchases.isEmpty {
                    ContentUnavailableView(
                        "No receipts yet",
                        systemImage: "doc.text",
                        description: Text("Scan or add a purchase and iPrint will tell you before the return window closes.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if ReceiptCamera.isAvailable {
                        Button("Scan", systemImage: "camera") { isScanning = true }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) { AddPurchaseView() }
            .fullScreenCover(isPresented: $isScanning) {
                ReceiptCamera { image in
                    isScanning = false
                    guard let image else { return }
                    Task { await process(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $draft) { draft in
                AddPurchaseView(prefill: draft.parsed)
            }
            .overlay {
                if isReadingReceipt {
                    ReadingReceiptOverlay()
                }
            }
            .alert("Couldn't read that receipt",
                   isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanError ?? "")
            }
        } detail: {
            if let selection {
                PurchaseDetailView(purchase: selection)
            } else {
                ContentUnavailableView("Select a purchase", systemImage: "sidebar.left")
            }
        }
    }

    /// OCR the scanned page and parse it, then open the confirm form so the
    /// user can correct the read before it saves and the receipt prints.
    private func process(_ image: UIImage) async {
        isReadingReceipt = true
        defer { isReadingReceipt = false }

        guard let data = image.jpegData(compressionQuality: 0.9) else {
            scanError = "The scanned image could not be processed."
            return
        }

        let lines: [String]
        do {
            lines = try await ReceiptOCR.recognizeLines(from: data)
        } catch {
            scanError = "Text recognition failed. Try again in better light."
            return
        }

        draft = ScanDraft(parsed: ReceiptParser.parse(lines))
    }

    /// Delete swiped rows: cancel their pending alerts, drop the detail
    /// selection if it pointed at a deleted row, then remove from the store.
    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { purchases[$0] }
        for purchase in doomed {
            if selection == purchase { selection = nil }
            let id = purchase.id
            Task { await NotificationScheduler.shared.cancel(purchaseID: id) }
            context.delete(purchase)
        }
    }
}

/// Identifiable wrapper so a parsed scan can drive a `.sheet(item:)`.
private struct ScanDraft: Identifiable {
    let id = UUID()
    let parsed: ParsedReceipt
}

private struct ReadingReceiptOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Reading receipt…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        }
    }
}

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
    @State private var searchText = ""
    @State private var sort: SortOption = .dateNewest

    /// The `@Query` fetches everything; search and sort are applied in memory.
    /// A personal receipt vault is small enough that this stays cheap and
    /// keeps the query itself simple.
    private var visiblePurchases: [StoredPurchase] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? purchases : purchases.filter {
            $0.merchant.lowercased().contains(query)
                || $0.category.displayName.lowercased().contains(query)
                || $0.note.lowercased().contains(query)
        }
        return filtered.sorted(by: sort.areInOrder)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visiblePurchases) { purchase in
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
            .searchable(text: $searchText, prompt: "Merchant, category, or note")
            .overlay {
                if purchases.isEmpty {
                    ContentUnavailableView(
                        "No receipts yet",
                        systemImage: "doc.text",
                        description: Text("Scan or add a purchase and iPrint will tell you before the return window closes.")
                    )
                } else if visiblePurchases.isEmpty {
                    ContentUnavailableView.search(text: searchText)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Sort", systemImage: "arrow.up.arrow.down") {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }
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
    /// Offsets index the currently visible (filtered/sorted) list.
    private func delete(at offsets: IndexSet) {
        let visible = visiblePurchases
        let doomed = offsets.map { visible[$0] }
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

/// Ways to order the vault. `areInOrder` gives each case a sort predicate so
/// the view stays declarative.
private enum SortOption: String, CaseIterable, Identifiable {
    case dateNewest, dateOldest, merchant, amountHigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateNewest: "Newest first"
        case .dateOldest: "Oldest first"
        case .merchant:   "Merchant (A–Z)"
        case .amountHigh: "Amount (high–low)"
        }
    }

    func areInOrder(_ a: StoredPurchase, _ b: StoredPurchase) -> Bool {
        switch self {
        case .dateNewest: a.purchaseDate > b.purchaseDate
        case .dateOldest: a.purchaseDate < b.purchaseDate
        case .merchant:   a.merchant.localizedCaseInsensitiveCompare(b.merchant) == .orderedAscending
        case .amountHigh: a.totalCentsRaw > b.totalCentsRaw
        }
    }
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

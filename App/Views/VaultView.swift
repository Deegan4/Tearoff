import SwiftUI
import SwiftData
import VaultCore

struct VaultView: View {
    @Query(sort: \StoredPurchase.purchaseDate, order: .reverse)
    private var purchases: [StoredPurchase]

    @State private var selection: StoredPurchase?
    @State private var isAdding = false

    var body: some View {
        NavigationSplitView {
            List(purchases, selection: $selection) { purchase in
                NavigationLink(value: purchase) {
                    PurchaseRow(
                        purchase: purchase,
                        returnWindow: ResolverStore.shared.returnWindow(for: purchase)
                    )
                }
            }
            .navigationTitle("Vault")
            .overlay {
                if purchases.isEmpty {
                    ContentUnavailableView(
                        "No receipts yet",
                        systemImage: "doc.text",
                        description: Text("Add a purchase and iPrint will tell you before the return window closes.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) { AddPurchaseView() }
        } detail: {
            if let selection {
                PurchaseDetailView(purchase: selection)
            } else {
                ContentUnavailableView("Select a purchase", systemImage: "sidebar.left")
            }
        }
    }
}

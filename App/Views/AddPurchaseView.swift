import SwiftUI
import SwiftData
import VaultCore

struct AddPurchaseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var merchant = ""
    @State private var purchaseDate = Date()
    @State private var amountText = ""
    @State private var category: PurchaseCategory = .other
    @State private var note = ""

    private var amountCents: Cents? {
        // Parse dollars-and-cents input into exact minor units without
        // ever routing through a binary floating-point value.
        let cleaned = amountText.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let dollars = Int(parts[0].isEmpty ? "0" : parts[0]) else { return nil }
        var cents = 0
        if parts.count == 2 {
            let frac = (parts[1] + "00").prefix(2)
            guard let parsed = Int(frac) else { return nil }
            cents = parsed
        }
        return Cents(dollars * 100 + cents)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase") {
                    TextField("Merchant", text: $merchant)
                    DatePicker("Date", selection: $purchaseDate, displayedComponents: .date)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Category", selection: $category) {
                        ForEach(PurchaseCategory.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }

                if !category.isReturnable {
                    Section {
                        Text("\(category.displayName) purchases are not tracked for returns.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Purchase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty || amountCents == nil)
                }
            }
        }
    }

    private func save() {
        guard let cents = amountCents else { return }
        let purchase = StoredPurchase(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            purchaseDate: purchaseDate,
            totalCents: cents,
            category: category,
            note: note
        )
        context.insert(purchase)

        let id = purchase.id
        let name = purchase.merchant
        let returnWindow = ResolverStore.shared.returnWindow(for: purchase)
        let warranty = ResolverStore.shared.warrantyWindow(for: purchase)

        Task {
            await NotificationScheduler.shared.schedule(
                purchaseID: id,
                merchant: name,
                returnWindow: returnWindow,
                warranty: warranty
            )
        }

        dismiss()
    }
}

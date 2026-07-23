import SwiftUI
import SwiftData
import VaultCore

/// Create, confirm-a-scan, or edit a purchase. The same form backs all
/// three so the return/warranty window fields — and the provenance ladder
/// they drive — are reachable everywhere.
struct AddPurchaseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var merchant: String
    @State private var purchaseDate: Date
    @State private var amountText: String
    @State private var category: PurchaseCategory
    @State private var note: String

    @State private var printedReturnOn: Bool
    @State private var printedReturnDays: Int
    @State private var userReturnOn: Bool
    @State private var userReturnDays: Int

    @State private var printedWarrantyOn: Bool
    @State private var printedWarrantyMonths: Int
    @State private var userWarrantyOn: Bool
    @State private var userWarrantyMonths: Int

    @State private var printed: StoredPurchase?

    private let editing: StoredPurchase?
    private let fromScan: Bool

    // MARK: Init

    /// Blank for manual entry, or seeded from an OCR result so a scan becomes
    /// an editable confirm step before the receipt prints.
    init(prefill: ParsedReceipt? = nil) {
        editing = nil
        fromScan = prefill != nil
        _merchant = State(initialValue: prefill?.merchant ?? "")
        _purchaseDate = State(initialValue: prefill?.date ?? Date())
        _amountText = State(initialValue: Self.amountString(prefill?.totalCents))
        _category = State(initialValue: prefill?.category ?? .other)
        _note = State(initialValue: prefill != nil ? "Scanned receipt" : "")
        // Pre-arm the printed-window toggles when the scan read a term off
        // the slip, so the user confirms rather than re-enters it.
        _printedReturnOn = State(initialValue: prefill?.printedReturnDays != nil)
        _printedReturnDays = State(initialValue: prefill?.printedReturnDays ?? 30)
        _userReturnOn = State(initialValue: false)
        _userReturnDays = State(initialValue: 30)
        _printedWarrantyOn = State(initialValue: prefill?.printedWarrantyMonths != nil)
        _printedWarrantyMonths = State(initialValue: prefill?.printedWarrantyMonths ?? 12)
        _userWarrantyOn = State(initialValue: false)
        _userWarrantyMonths = State(initialValue: 12)
    }

    /// Edit an existing purchase in place.
    init(editing purchase: StoredPurchase) {
        editing = purchase
        fromScan = false
        _merchant = State(initialValue: purchase.merchant)
        _purchaseDate = State(initialValue: purchase.purchaseDate)
        _amountText = State(initialValue: Self.amountString(purchase.totalCents))
        _category = State(initialValue: purchase.category)
        _note = State(initialValue: purchase.note)
        _printedReturnOn = State(initialValue: purchase.printedWindowDays != nil)
        _printedReturnDays = State(initialValue: purchase.printedWindowDays ?? 30)
        _userReturnOn = State(initialValue: purchase.userWindowDays != nil)
        _userReturnDays = State(initialValue: purchase.userWindowDays ?? 30)
        _printedWarrantyOn = State(initialValue: purchase.printedWarrantyMonths != nil)
        _printedWarrantyMonths = State(initialValue: purchase.printedWarrantyMonths ?? 12)
        _userWarrantyOn = State(initialValue: purchase.userWarrantyMonths != nil)
        _userWarrantyMonths = State(initialValue: purchase.userWarrantyMonths ?? 12)
    }

    private static func amountString(_ cents: Cents?) -> String {
        guard let cents, cents.raw > 0 else { return "" }
        return String(format: "%d.%02d", cents.raw / 100, cents.raw % 100)
    }

    // MARK: Derived

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

    private var printedReturn: Int? { printedReturnOn ? printedReturnDays : nil }
    private var userReturn: Int? { userReturnOn ? userReturnDays : nil }
    private var printedWarranty: Int? { printedWarrantyOn ? printedWarrantyMonths : nil }
    private var userWarranty: Int? { userWarrantyOn ? userWarrantyMonths : nil }

    private var returnPreview: WindowResolution? {
        ResolverStore.shared.policy.resolve(
            merchant: merchant, category: category, purchaseDate: purchaseDate,
            printedWindowDays: printedReturn, userWindowDays: userReturn
        )
    }

    private var warrantyPreview: WindowResolution? {
        ResolverStore.shared.warranty.resolve(
            category: category, purchaseDate: purchaseDate,
            printedMonths: printedWarranty, userMonths: userWarranty
        )
    }

    // MARK: Body

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

                if category.isReturnable {
                    returnSection
                    warrantySection
                } else {
                    Section {
                        Text("\(category.displayName) purchases are not tracked for returns.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Save" : "Done") { save() }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty || amountCents == nil)
                }
            }
            .fullScreenCover(item: $printed) { purchase in
                ReceiptPrintView(purchase: purchase) { dismiss() }
            }
        }
    }

    private var title: String {
        if editing != nil { return "Edit Purchase" }
        return fromScan ? "Confirm Receipt" : "Add Purchase"
    }

    private var returnSection: some View {
        Section {
            Toggle("Printed on receipt", isOn: $printedReturnOn)
            if printedReturnOn {
                Stepper("\(printedReturnDays) days", value: $printedReturnDays, in: 1...365)
            }
            Toggle("Set return window manually", isOn: $userReturnOn)
            if userReturnOn {
                Stepper("\(userReturnDays) days", value: $userReturnDays, in: 1...365)
            }
        } header: {
            Text("Return window")
        } footer: {
            resolutionFooter(returnPreview, emptyText: "No return window known — the retailer table decides, or nothing shows.")
        }
    }

    private var warrantySection: some View {
        Section {
            Toggle("Printed on receipt", isOn: $printedWarrantyOn)
            if printedWarrantyOn {
                Stepper("\(printedWarrantyMonths) months", value: $printedWarrantyMonths, in: 1...120)
            }
            Toggle("Set warranty manually", isOn: $userWarrantyOn)
            if userWarrantyOn {
                Stepper("\(userWarrantyMonths) months", value: $userWarrantyMonths, in: 1...120)
            }
        } header: {
            Text("Warranty")
        } footer: {
            resolutionFooter(warrantyPreview, emptyText: "No warranty term known — a category estimate may apply.")
        }
    }

    @ViewBuilder
    private func resolutionFooter(_ resolution: WindowResolution?, emptyText: String) -> some View {
        if let r = resolution {
            Text("Resolves to \(r.deadline.formatted(date: .abbreviated, time: .omitted)) — \(r.provenance.explanation)")
                .foregroundStyle(r.provenance.isEstimate ? .orange : .secondary)
        } else {
            Text(emptyText)
        }
    }

    // MARK: Save

    private func save() {
        guard let cents = amountCents else { return }
        let target: StoredPurchase

        if let existing = editing {
            existing.merchant = merchant.trimmingCharacters(in: .whitespaces)
            existing.purchaseDate = purchaseDate
            existing.totalCents = cents
            existing.category = category
            existing.note = note
            target = existing
        } else {
            target = StoredPurchase(
                merchant: merchant.trimmingCharacters(in: .whitespaces),
                purchaseDate: purchaseDate,
                totalCents: cents,
                category: category,
                note: note
            )
            context.insert(target)
        }

        target.printedWindowDays = printedReturn
        target.userWindowDays = userReturn
        target.printedWarrantyMonths = printedWarranty
        target.userWarrantyMonths = userWarranty

        let id = target.id
        let name = target.merchant
        let returnWindow = ResolverStore.shared.returnWindow(for: target)
        let warranty = ResolverStore.shared.warrantyWindow(for: target)
        Task {
            await NotificationScheduler.shared.schedule(
                purchaseID: id,
                merchant: name,
                returnWindow: returnWindow,
                warranty: warranty
            )
        }

        // Print the (updated) receipt; its Done button dismisses the form.
        printed = target
    }
}

import SwiftUI
import SwiftData
import VaultCore

/// Create, confirm-a-scan, or edit a purchase. The same form backs all
/// three so the return/warranty window fields — and the provenance ladder
/// they drive — are reachable everywhere.
struct AddPurchaseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store

    @State private var merchant: String
    @State private var purchaseDate: Date
    @State private var amountText: String
    @State private var category: PurchaseCategory
    @State private var note: String
    @State private var barcode: String
    @State private var scanningBarcode = false
    @State private var paymentMethod: String
    @State private var orderNumber: String
    @State private var showingPaywall = false

    // Captured from the scan (or existing record) and carried onto save. Not
    // free-text edited here, so held as plain values rather than @State.
    private let subtotalCents: Cents?
    private let taxCents: Cents?
    private let lineItems: [LineItem]

    @State private var printedReturnOn: Bool
    @State private var printedReturnDays: Int
    @State private var userReturnOn: Bool
    @State private var userReturnDays: Int

    @State private var printedWarrantyOn: Bool
    @State private var printedWarrantyMonths: Int
    @State private var userWarrantyOn: Bool
    @State private var userWarrantyMonths: Int

    @State private var printed: StoredPurchase?

    // Pro feature: the store's location, for the proximity reminder.
    @State private var storeLatitude: Double?
    @State private var storeLongitude: Double?
    @State private var isLocatingStore = false

    private let editing: StoredPurchase?
    private let fromScan: Bool
    /// Set only on the scan path; carried onto the new record at save time.
    private let receiptImageData: Data?
    /// What the scanner produced, snapshotted at prefill so the save path can
    /// diff it against the user's confirmed values for accuracy telemetry.
    private let scanParsed: ExtractionSnapshot?

    // MARK: Init

    /// Blank for manual entry, or seeded from an OCR result so a scan becomes
    /// an editable confirm step before the receipt prints.
    init(prefill: ParsedReceipt? = nil, receiptImageData: Data? = nil) {
        editing = nil
        fromScan = prefill != nil
        self.receiptImageData = receiptImageData
        scanParsed = prefill.map { p in
            ExtractionSnapshot(
                merchant: p.merchant,
                date: p.date,
                totalCents: p.totalCents,
                category: p.category,
                returnDays: p.printedReturnDays,
                warrantyMonths: p.printedWarrantyMonths,
                paymentMethod: p.paymentMethod,
                orderNumber: p.orderNumber
            )
        }
        _merchant = State(initialValue: prefill?.merchant ?? "")
        _purchaseDate = State(initialValue: prefill?.date ?? Date())
        _amountText = State(initialValue: Self.amountString(prefill?.totalCents))
        _category = State(initialValue: prefill?.category ?? .other)
        _note = State(initialValue: prefill != nil ? "Scanned receipt" : "")
        _barcode = State(initialValue: "")
        _paymentMethod = State(initialValue: prefill?.paymentMethod ?? "")
        _orderNumber = State(initialValue: prefill?.orderNumber ?? "")
        subtotalCents = prefill?.subtotalCents
        taxCents = prefill?.taxCents
        lineItems = prefill?.lineItems ?? []
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
        _storeLatitude = State(initialValue: nil)
        _storeLongitude = State(initialValue: nil)
    }

    /// Edit an existing purchase in place.
    init(editing purchase: StoredPurchase) {
        editing = purchase
        fromScan = false
        receiptImageData = nil   // editing preserves the record's existing image
        scanParsed = nil         // telemetry only measures the scan → confirm path
        _merchant = State(initialValue: purchase.merchant)
        _purchaseDate = State(initialValue: purchase.purchaseDate)
        _amountText = State(initialValue: Self.amountString(purchase.totalCents))
        _category = State(initialValue: purchase.category)
        _note = State(initialValue: purchase.note)
        _barcode = State(initialValue: purchase.barcode)
        _paymentMethod = State(initialValue: purchase.paymentMethod)
        _orderNumber = State(initialValue: purchase.orderNumber)
        subtotalCents = purchase.subtotalCents
        taxCents = purchase.taxCents
        lineItems = purchase.lineItems
        _printedReturnOn = State(initialValue: purchase.printedWindowDays != nil)
        _printedReturnDays = State(initialValue: purchase.printedWindowDays ?? 30)
        _userReturnOn = State(initialValue: purchase.userWindowDays != nil)
        _userReturnDays = State(initialValue: purchase.userWindowDays ?? 30)
        _printedWarrantyOn = State(initialValue: purchase.printedWarrantyMonths != nil)
        _printedWarrantyMonths = State(initialValue: purchase.printedWarrantyMonths ?? 12)
        _userWarrantyOn = State(initialValue: purchase.userWarrantyMonths != nil)
        _userWarrantyMonths = State(initialValue: purchase.userWarrantyMonths ?? 12)
        _storeLatitude = State(initialValue: purchase.storeLatitude)
        _storeLongitude = State(initialValue: purchase.storeLongitude)
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
                    if store.isPro { storeLocationSection }
                    // Warranty tracking is a Pro feature; free users see an
                    // upsell instead of the warranty controls.
                    if store.isPro {
                        warrantySection
                    } else {
                        warrantyLockedSection
                    }
                } else {
                    Section {
                        Text("\(category.displayName) purchases are not tracked for returns.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    if let subtotalCents {
                        LabeledContent("Subtotal", value: subtotalCents.formatted(currencyCode: "USD"))
                    }
                    if let taxCents {
                        LabeledContent("Tax", value: taxCents.formatted(currencyCode: "USD"))
                    }
                    TextField("Payment method", text: $paymentMethod)
                    TextField("Order / transaction #", text: $orderNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if !lineItems.isEmpty {
                    Section("Items (\(lineItems.count))") {
                        ForEach(lineItems, id: \.self) { item in
                            HStack {
                                Text(item.name)
                                Spacer(minLength: 12)
                                Text(Cents(item.cents).formatted(currencyCode: "USD"))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Barcode") {
                    HStack {
                        TextField("Product barcode (optional)", text: $barcode)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if BarcodeScanner.isAvailable {
                            Button("Scan barcode", systemImage: "barcode.viewfinder") {
                                scanningBarcode = true
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(title)
            // A sheet, not a second fullScreenCover, so it never conflicts with
            // the receipt cover on this same view.
            .sheet(isPresented: $scanningBarcode) {
                BarcodeScanner { code in
                    barcode = code
                    scanningBarcode = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(store: store, valueInWindowCents: 0)
            }
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

    /// Pro feature: tag the purchase with the store's location so Settings'
    /// "Remind me near a store" toggle has something to check against.
    private var storeLocationSection: some View {
        Section {
            Button {
                Task {
                    isLocatingStore = true
                    defer { isLocatingStore = false }
                    if let coordinate = await ProximityReminder.shared.captureCurrentLocation() {
                        storeLatitude = coordinate.latitude
                        storeLongitude = coordinate.longitude
                    }
                }
            } label: {
                if isLocatingStore {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label(storeLatitude == nil ? "Set store location" : "Update store location",
                          systemImage: "location")
                }
            }
            .disabled(isLocatingStore)
            if storeLatitude != nil {
                Button("Clear store location", role: .destructive) {
                    storeLatitude = nil
                    storeLongitude = nil
                }
            }
        } header: {
            Text("Store location")
        } footer: {
            Text("Set this while you're at the store. Enables a nudge if you're back nearby with the return window still open.")
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

    private var warrantyLockedSection: some View {
        Section {
            Button {
                showingPaywall = true
            } label: {
                HStack {
                    Label("Warranty tracking", systemImage: "lock.fill")
                    Spacer()
                    Text("Pro")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
        } header: {
            Text("Warranty")
        } footer: {
            Text("Track manufacturer warranty deadlines alongside returns with Tearoff Pro.")
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
            existing.barcode = barcode.trimmingCharacters(in: .whitespaces)
            target = existing
        } else {
            target = StoredPurchase(
                merchant: merchant.trimmingCharacters(in: .whitespaces),
                purchaseDate: purchaseDate,
                totalCents: cents,
                category: category,
                note: note
            )
            target.receiptImageData = receiptImageData
            target.barcode = barcode.trimmingCharacters(in: .whitespaces)
            context.insert(target)
        }

        // Store location is Pro-gated, same as warranty tracking below.
        target.storeLatitude = store.isPro ? storeLatitude : nil
        target.storeLongitude = store.isPro ? storeLongitude : nil

        // Warranty tracking is Pro-gated: free users never persist a warranty
        // term or receive warranty alerts, even if a scan pre-armed one.
        let effectivePrintedWarranty = store.isPro ? printedWarranty : nil
        let effectiveUserWarranty = store.isPro ? userWarranty : nil

        target.printedWindowDays = printedReturn
        target.userWindowDays = userReturn
        target.printedWarrantyMonths = effectivePrintedWarranty
        target.userWarrantyMonths = effectiveUserWarranty

        // Extra receipt details (both new and edited records).
        target.paymentMethod = paymentMethod.trimmingCharacters(in: .whitespaces)
        target.orderNumber = orderNumber.trimmingCharacters(in: .whitespaces)
        target.subtotalCentsRaw = subtotalCents?.raw ?? 0
        target.taxCentsRaw = taxCents?.raw ?? 0
        target.lineItems = lineItems

        // Record how much of the scan the user had to correct (scan path only,
        // counts only — see ExtractionTelemetryStore).
        if let scanParsed {
            let confirmed = ExtractionSnapshot(
                merchant: target.merchant,
                date: target.purchaseDate,
                totalCents: cents,
                category: target.category,
                returnDays: printedReturn,
                warrantyMonths: printedWarranty,
                paymentMethod: target.paymentMethod,
                orderNumber: target.orderNumber
            )
            ExtractionTelemetryStore.shared.record(parsed: scanParsed, saved: confirmed)
        }

        let id = target.id
        let name = target.merchant
        let returnWindow = ResolverStore.shared.returnWindow(for: target)
        // No warranty alerts for free users, including category-default estimates.
        let warranty = store.isPro ? ResolverStore.shared.warrantyWindow(for: target) : nil
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

import SwiftUI
import SwiftData
import UIKit
import VaultCore

struct VaultView: View {
    @Environment(\.modelContext) private var context
    @Environment(StoreManager.self) private var store

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
    @State private var showingSettings = false
    @State private var showingPaywall = false
    /// Observed so Siri / Shortcuts intents can drive navigation.
    private let router = IntentRouter.shared
    @Namespace private var heroNS

    /// A cheap change-signature over the fields that affect the widget digest,
    /// so we republish only when a deadline could actually have changed.
    private var digestSignature: Int {
        var hasher = Hasher()
        for p in purchases {
            hasher.combine(p.id)
            hasher.combine(p.purchaseDate)
            hasher.combine(p.statusRaw)
            hasher.combine(p.categoryRaw)
            hasher.combine(p.printedWindowDays)
            hasher.combine(p.userWindowDays)
            hasher.combine(p.printedWarrantyMonths)
            hasher.combine(p.userWarrantyMonths)
        }
        return hasher.finalize()
    }

    /// Value of purchases still inside an open return window — the paywall's
    /// insurance-shaped pitch (spec §7). Active status, deadline not yet past.
    private var valueInOpenReturnWindowCents: Int {
        let today = Date()
        return purchases.reduce(0) { sum, purchase in
            guard !purchase.status.isResolved,
                  let window = ResolverStore.shared.returnWindow(for: purchase),
                  window.deadline >= today else { return sum }
            return sum + purchase.totalCents.raw
        }
    }

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
                    // Hero: the tapped row is the zoom source that the detail
                    // view morphs out of (and back into on dismiss).
                    .matchedTransitionSource(id: purchase.id, in: heroNS)
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Vault")
            // Reorders when the sort changes settle with the house spring.
            .animation(Motion.premium, value: sort)
            .searchable(text: $searchText, prompt: "Merchant, category, or note")
            .overlay {
                if purchases.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No receipts yet")
                        } icon: {
                            // The icon breathes with a gentle periodic bounce so
                            // the blank screen feels alive, not dead.
                            Image(systemName: "doc.text")
                                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2.5)))
                        }
                    } description: {
                        Text("Scan or add a purchase and Tearoff will tell you before the return window closes.")
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else if visiblePurchases.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .transition(.opacity)
                }
            }
            .animation(Motion.alive, value: purchases.isEmpty)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if ReceiptCamera.isAvailable {
                        // Camera scan is a Pro feature; free users get the
                        // paywall instead of the camera.
                        Button("Scan", systemImage: "camera") {
                            if store.isPro { isScanning = true } else { showingPaywall = true }
                        }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $isAdding) { AddPurchaseView() }
            .task { WidgetBridge.publish(purchases); await LiveActivityManager.sync(purchases) }
            .onChange(of: digestSignature) {
                WidgetBridge.publish(purchases)
                Task { @MainActor in await LiveActivityManager.sync(purchases) }
            }
            // Siri / Shortcuts navigation: an intent set a route; act on it, then clear.
            .onChange(of: router.pendingRoute) { _, route in
                switch route {
                case .add: isAdding = true
                case .scan: if store.isPro { isScanning = true } else { showingPaywall = true }
                case nil: break
                }
                if route != nil { router.pendingRoute = nil }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(store: store, valueInWindowCents: valueInOpenReturnWindowCents)
            }
            .fullScreenCover(isPresented: $isScanning) {
                ReceiptCamera { image in
                    isScanning = false
                    guard let image else { return }
                    Task { await process(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $draft) { draft in
                AddPurchaseView(prefill: draft.parsed, receiptImageData: draft.imageData)
            }
            .overlay {
                if isReadingReceipt {
                    ReadingReceiptOverlay()
                }
            }
            .animation(Motion.snappy, value: isReadingReceipt)
            .alert("Couldn't read that receipt",
                   isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanError ?? "")
            }
        } detail: {
            if let selection {
                PurchaseDetailView(purchase: selection)
                    .navigationTransition(.zoom(sourceID: selection.id, in: heroNS))
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

        // OCR runs on the full-resolution capture above; keep a downsampled
        // copy of the same image to store with the record.
        draft = ScanDraft(
            parsed: ReceiptParser.parse(lines),
            imageData: ReceiptImage.forStorage(image)
        )
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
    /// Downsampled JPEG of the scanned page, retained on the saved record.
    var imageData: Data?
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
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                ScanningCard()
                Text("Reading receipt…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
        }
        .transition(.opacity.combined(with: .scale(scale: 1.04)))
    }
}

/// A receipt silhouette with a soft light bar sweeping down it, evoking the
/// OCR pass. The sweep is a continuous phase animation — one lightweight
/// element, so it stays smooth without touching the row list underneath.
private struct ScanningCard: View {
    private let size = CGSize(width: 118, height: 150)

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white.opacity(0.08))
            .overlay(receiptLines.padding(16))
            .overlay(scanBeam)
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
    }

    private var receiptLines: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(height: 4)
                    .padding(.trailing, [0, 34, 12, 40, 0, 22][i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanBeam: some View {
        PhaseAnimator([0.0, 1.0]) { t in
            LinearGradient(
                colors: [.clear, .white.opacity(0.9), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 24)
            .blur(radius: 3)
            .offset(y: -size.height / 2 + t * size.height)
        } animation: { _ in
            .easeInOut(duration: 1.25)
        }
    }
}

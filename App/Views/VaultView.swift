import SwiftUI
import SwiftData
import UIKit
import VaultCore

struct VaultView: View {
    @Environment(\.modelContext) private var context
    @Environment(StoreManager.self) private var store
    @Environment(\.scenePhase) private var scenePhase

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
    @AppStorage("proximityRemindersEnabled") private var proximityRemindersEnabled = false
    /// Shown once, ever — a soft nudge toward scanning, never a hard cap.
    /// The vault itself stays unlimited on Free; see the design note above
    /// `scanUpsellThreshold`.
    @AppStorage("hasSeenScanUpsell") private var hasSeenScanUpsell = false
    /// Lifetime count of free scans spent. Device-local on purpose: it is not
    /// synced, so it is not a licence — it exists to let the extraction sell
    /// itself once, not to be defended against a reinstall.
    @AppStorage("freeScansUsed") private var freeScansUsed = 0
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
    /// insurance-shaped pitch (spec §7). Computed once in VaultCore.
    private var valueInOpenReturnWindowCents: Int {
        ResolverStore.shared.insights(for: purchases).openReturnValueCents
    }

    /// Purchases typed in by hand rather than scanned — `receiptImageData` is
    /// only ever set on the scan path (see AddPurchaseView), so its absence
    /// is a reliable proxy for "this one was manual work."
    private var manualEntryCount: Int {
        purchases.count { $0.receiptImageData == nil }
    }

    /// The vault itself is never capped — Free is "manual receipts, alerts,
    /// full vault" (spec §7) and staying unlimited is the trust pitch for a
    /// receipt vault. This is a one-time nudge toward Pro scanning once
    /// manual entry has clearly become a chore, not a paywall in disguise.
    private let scanUpsellThreshold = 8

    private var shouldShowScanUpsell: Bool {
        !store.isPro && !hasSeenScanUpsell && manualEntryCount >= scanUpsellThreshold
    }

    /// Free users get a few lifetime scans before the paywall, so the camera
    /// gets to prove itself first. See `ScanAllowance` for the reasoning.
    private var allowance: ScanAllowance {
        ScanAllowance(isPro: store.isPro, freeScansUsed: freeScansUsed)
    }

    /// Opens the camera if there's an allowance left, else the paywall.
    private func startScanOrPaywall() {
        if allowance.canScan { isScanning = true } else { showingPaywall = true }
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
                if shouldShowScanUpsell {
                    scanUpsellRow
                }
                if allowance.shouldShowRemainingCount, let left = allowance.remaining {
                    freeScansRow(left)
                }
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
                    // Rows settle in as they enter the viewport — the correct
                    // list idiom (a onAppear stagger re-fires on cell reuse).
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.35)
                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Vault")
            // Reorders when the sort changes settle with the house spring.
            .animation(Motion.premium, value: sort)
            .animation(Motion.premium, value: hasSeenScanUpsell)
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
                        // Camera scan is a Pro feature, but free users get a
                        // small lifetime allowance first — the paywall lands
                        // once the extraction has shown what it does.
                        Button("Scan", systemImage: "camera") { startScanOrPaywall() }
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
            .task { drainPendingReturns(); WidgetBridge.publish(purchases, isPro: store.isPro); await LiveActivityManager.sync(purchases) }
            // A widget "Mark returned" tap only queues the change; apply it when
            // the app comes forward so SwiftData and the alerts stay in sync.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    drainPendingReturns()
                    if store.isPro && proximityRemindersEnabled {
                        Task { await ProximityReminder.shared.checkNearbyStores(purchases: purchases) }
                    }
                }
            }
            .onChange(of: digestSignature) {
                WidgetBridge.publish(purchases, isPro: store.isPro)
                Task { @MainActor in await LiveActivityManager.sync(purchases) }
            }
            .onChange(of: store.isPro) {
                WidgetBridge.publish(purchases, isPro: store.isPro)
            }
            // Siri / Shortcuts navigation: an intent set a route; act on it, then clear.
            .onChange(of: router.pendingRoute) { _, route in
                switch route {
                case .add: isAdding = true
                case .scan: startScanOrPaywall()
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

        // Only spend a free scan once extraction actually reached the confirm
        // step. Both failure paths above return early, so a scan that couldn't
        // be read (bad light, unreadable slip) costs the user nothing.
        if !store.isPro { freeScansUsed += 1 }

        // OCR runs on the full-resolution capture above; keep a downsampled
        // copy of the same image to store with the record.
        draft = ScanDraft(
            parsed: ReceiptParser.parse(lines),
            imageData: ReceiptImage.forStorage(image)
        )
    }

    /// One-time nudge row: "you've typed N receipts by hand, scanning is
    /// faster" — dismissible, and marked seen either way so it never nags
    /// twice.
    /// Standing note of how much of the free scan allowance is left. Appears
    /// only after the first scan, so it reads as what remains of a gift rather
    /// than as a restriction announced up front.
    private func freeScansRow(_ left: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: left == 0 ? "camera.badge.ellipsis" : "camera.viewfinder")
                .font(.title3)
                .foregroundStyle(left == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(left == 0
                     ? "Free scans used up"
                     : "\(left) free scan\(left == 1 ? "" : "s") left")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText(countsDown: true))
                Text(left == 0
                     ? "Pro keeps scanning unlimited. Typing receipts in by hand stays free forever."
                     : "Then scanning becomes a Pro feature. Everything you've already saved stays yours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if left == 0 {
                    Button("See Pro") { showingPaywall = true }
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.accentColor.opacity(left == 0 ? 0.04 : 0.08))
        .animation(Motion.snappy, value: left)
    }

    private var scanUpsellRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("Typing gets old")
                    .font(.subheadline.weight(.semibold))
                // Don't sell Pro scanning to someone who still has free scans
                // sitting unused — point them at the camera instead. Selling a
                // feature the user already has is the fastest way to look like
                // the app isn't paying attention.
                if allowance.canScan {
                    Text("You've logged \(manualEntryCount) receipts by hand. Scanning takes about 2 seconds — you have \(allowance.remaining ?? 0) free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Scan one instead") {
                        hasSeenScanUpsell = true
                        startScanOrPaywall()
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                } else {
                    Text("You've logged \(manualEntryCount) receipts by hand. Pro scans one in about 2 seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try Pro scanning") {
                        hasSeenScanUpsell = true
                        showingPaywall = true
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Button {
                hasSeenScanUpsell = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.accentColor.opacity(0.08))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Apply any "Mark returned" taps the widget queued while the app wasn't
    /// running: flip each purchase to `.returned`, cancel its alerts, then clear
    /// the queue. Mutating `statusRaw` moves `digestSignature`, which republishes
    /// the widget digest from the true model — reconciling the intent's
    /// optimistic write.
    private func drainPendingReturns() {
        let queue = PendingReturnStore()
        let ids = queue.pending()
        guard !ids.isEmpty else { return }
        let wanted = Set(ids.compactMap { UUID(uuidString: $0) })
        for purchase in purchases where wanted.contains(purchase.id) && !purchase.status.isResolved {
            purchase.status = .returned
            let id = purchase.id
            Task { await NotificationScheduler.shared.cancel(purchaseID: id) }
        }
        // Clear only what we saw, so a tap that lands mid-drain isn't dropped.
        queue.remove(ids)
        drainPendingSnoozes()
    }

    /// Apply any "Snooze" taps queued from the widget: push that purchase's
    /// return reminder out to the requested date.
    private func drainPendingSnoozes() {
        let queue = PendingSnoozeStore()
        let entries = queue.pending()
        guard !entries.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.purchaseID, $0.until) })
        for purchase in purchases where !purchase.status.isResolved {
            guard let until = byID[purchase.id.uuidString] else { continue }
            let id = purchase.id
            let merchant = purchase.merchant
            Task { await NotificationScheduler.shared.snoozeReturn(purchaseID: id, merchant: merchant, until: until) }
        }
        queue.remove(entries.map(\.purchaseID))
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

import SwiftUI
import SwiftData
import UIKit
import VaultCore

struct PurchaseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store

    let purchase: StoredPurchase
    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var actionMessage: String?
    @State private var proof: Image?
    @State private var showingPaywall = false
    @Environment(\.displayScale) private var displayScale
    // A single cover slot: presenting two `.fullScreenCover` modifiers on one
    // view is a SwiftUI bug where the second blocks the first from dismissing,
    // which left the receipt's Done button unable to close. One item-driven
    // cover avoids the conflict entirely.
    @State private var cover: DetailCover?

    private enum DetailCover: Identifiable {
        case receipt, scanImage
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section("Status") {
                Picker(selection: Binding(get: { purchase.status }, set: { setStatus($0) })) {
                    ForEach(PurchaseStatus.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                } label: {
                    Text("Status")
                }
                .pickerStyle(.menu)
            }
            .staggeredAppear(0)

            Section("Purchase") {
                LabeledContent("Merchant", value: purchase.merchant)
                LabeledContent("Date", value: purchase.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Total", value: purchase.totalCents.formatted(currencyCode: "USD"))
                LabeledContent("Category", value: purchase.category.displayName)
                if let subtotal = purchase.subtotalCents {
                    LabeledContent("Subtotal", value: subtotal.formatted(currencyCode: "USD"))
                }
                if let tax = purchase.taxCents {
                    LabeledContent("Tax", value: tax.formatted(currencyCode: "USD"))
                }
                if !purchase.paymentMethod.isEmpty {
                    LabeledContent("Payment", value: purchase.paymentMethod)
                }
                if !purchase.orderNumber.isEmpty {
                    LabeledContent("Order #") {
                        Text(purchase.orderNumber).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
                if !purchase.barcode.isEmpty {
                    LabeledContent("Barcode") {
                        Text(purchase.barcode)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .staggeredAppear(0)

            if !purchase.lineItems.isEmpty {
                Section("Items (\(purchase.lineItems.count))") {
                    ForEach(purchase.lineItems, id: \.self) { item in
                        HStack {
                            Text(item.name)
                            Spacer(minLength: 12)
                            Text(Cents(item.cents).formatted(currencyCode: "USD"))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .staggeredAppear(1)
            }

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

            returnActionsSection

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
                        cover = .scanImage
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
                Button("Receipt", systemImage: "printer") { cover = .receipt }
            }
            ToolbarItem(placement: .secondaryAction) {
                // ShareLink manages its own presentation, so it adds no extra
                // sheet/cover modifier to conflict with the ones above.
                if let proof {
                    ShareLink(
                        item: proof,
                        preview: SharePreview("\(purchase.merchant) — proof of purchase", image: proof)
                    ) {
                        Label("Share proof", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { renderProof() }
        .sheet(isPresented: $isEditing) {
            AddPurchaseView(editing: purchase)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store, valueInWindowCents: purchase.totalCents.raw)
        }
        .fullScreenCover(item: $cover) { which in
            switch which {
            case .receipt:
                ReceiptPrintView(purchase: purchase) { cover = nil }
            case .scanImage:
                if let data = purchase.receiptImageData, let image = UIImage(data: data) {
                    ReceiptImageViewer(image: image) { cover = nil }
                }
            }
        }
        .confirmationDialog("Delete this purchase?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deletePurchase)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the record and cancels its alerts.")
        }
        .alert("Return", isPresented: Binding(get: { actionMessage != nil }, set: { if !$0 { actionMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    /// One-tap actions for an open return window: jump to the retailer's returns
    /// page, copy the order number a clerk will ask for, or set a Reminder for
    /// the deadline. Shown only while the window is still open and unresolved.
    @ViewBuilder
    private var returnActionsSection: some View {
        if !purchase.status.isResolved,
           let window = ResolverStore.shared.returnWindow(for: purchase),
           window.deadline >= Calendar.current.startOfDay(for: .now) {
            Section("Start your return") {
                // The curated direct-to-retailer deep link is the Pro perk;
                // free users still get the generic search fallback for
                // unknown merchants, same as before this was gated.
                if RetailerLinks.isKnown(purchase.merchant) {
                    if store.isPro, let url = RetailerLinks.returnsURL(forMerchant: purchase.merchant) {
                        Link(destination: url) {
                            Label("Open \(purchase.merchant) returns page", systemImage: "arrow.up.forward.app")
                        }
                    } else {
                        Button { showingPaywall = true } label: {
                            HStack {
                                Label("Open \(purchase.merchant) returns page", systemImage: "arrow.up.forward.app")
                                Spacer()
                                Text("Pro")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.tint.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                } else if let url = RetailerLinks.returnsURL(forMerchant: purchase.merchant) {
                    Link(destination: url) {
                        Label("Search the return policy", systemImage: "arrow.up.forward.app")
                    }
                }
                if !purchase.orderNumber.isEmpty {
                    Button {
                        UIPasteboard.general.string = purchase.orderNumber
                        actionMessage = "Order number copied to the clipboard."
                    } label: {
                        Label("Copy order number", systemImage: "doc.on.doc")
                    }
                }
                Button {
                    let merchant = purchase.merchant
                    let deadline = window.deadline
                    Task {
                        let outcome = await ReturnReminder.add(merchant: merchant, deadline: deadline)
                        actionMessage = switch outcome {
                        case .added: "Reminder set for \(deadline.formatted(date: .abbreviated, time: .omitted))."
                        case .denied: "Reminders access is off — turn it on in Settings to set one."
                        case .failed: "Couldn't create the reminder."
                        }
                    }
                } label: {
                    Label("Remind me to return", systemImage: "bell.badge")
                }
            }
            .staggeredAppear(2)
        }
    }

    /// Render the shareable proof card once when the detail appears.
    @MainActor private func renderProof() {
        let card = ProofCard(
            purchase: purchase,
            returnWindow: ResolverStore.shared.returnWindow(for: purchase),
            warranty: ResolverStore.shared.warrantyWindow(for: purchase)
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let image = renderer.uiImage {
            proof = Image(uiImage: image)
        }
    }

    /// Change lifecycle status. Resolving cancels pending alerts; reactivating
    /// reschedules them from the current windows.
    private func setStatus(_ status: PurchaseStatus) {
        purchase.status = status
        let id = purchase.id
        if status.isResolved {
            Task { await NotificationScheduler.shared.cancel(purchaseID: id) }
        } else {
            let merchant = purchase.merchant
            let returnWindow = ResolverStore.shared.returnWindow(for: purchase)
            let warranty = ResolverStore.shared.warrantyWindow(for: purchase)
            Task {
                await NotificationScheduler.shared.schedule(
                    purchaseID: id, merchant: merchant,
                    returnWindow: returnWindow, warranty: warranty
                )
            }
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
                        withAnimation(Motion.snappy) {
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

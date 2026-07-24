import SwiftUI
import StoreKit
import VaultCore

/// Tearoff Pro paywall. Insurance-shaped framing (spec §7): the pitch is
/// computed from the user's own vault — the dollars they have on the line
/// right now — and the AI-extraction copy branches on whether the device can
/// actually run the model.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private var store: StoreManager

    /// Total value of purchases still inside an open return window, in cents.
    /// Drives the headline; zero falls back to generic copy.
    private let valueInWindowCents: Int

    init(store: StoreManager, valueInWindowCents: Int) {
        self.store = store
        self.valueInWindowCents = valueInWindowCents
    }

    private var modelAvailable: Bool { ModelAvailability.current.canExtract }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headline
                    benefits
                    products
                    restoreAndTerms
                }
                .padding()
            }
            .navigationTitle("Tearoff Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { if store.products.isEmpty { await store.loadProducts() } }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }   // purchase/restore succeeded elsewhere
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            if valueInWindowCents > 0 {
                Text("\(Cents(valueInWindowCents).formatted(currencyCode: "USD")) of your purchases are still inside a return window.")
                    .font(.title2.weight(.semibold))
                Text("One recovered return funds years of Tearoff. Pro scans the receipt so the deadline is caught before it closes.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Never miss a return window again.")
                    .font(.title2.weight(.semibold))
                Text("Pro turns a photo of a receipt into a tracked purchase, so the deadline is caught before it closes.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit(modelAvailable ? "camera.viewfinder" : "keyboard",
                    modelAvailable ? "Camera + AI receipt extraction" : "Fast manual capture",
                    modelAvailable
                        ? "Snap the slip; Tearoff reads merchant, date, total, and terms."
                        : "This device can't run on-device extraction, so scanning is manual — everything else below is included.")
            benefit("shield.lefthalf.filled", "Warranty tracking", "Track manufacturer warranty deadlines alongside returns.")
            benefit("square.and.arrow.up", "Export", "Get your vault out as a shareable record any time.")
            benefit("widget.small", "Widgets", "Upcoming deadlines on your Home Screen.")
        }
    }

    private func benefit(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var products: some View {
        if store.displayProducts.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical)
        } else {
            VStack(spacing: 10) {
                ForEach(store.displayProducts, id: \.id) { product in
                    Button {
                        Task { await store.purchase(product) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName).font(.callout.weight(.semibold))
                                Text(subtitle(for: product)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(product.displayPrice).font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isWorking)
                }
            }
        }
    }

    private func subtitle(for product: Product) -> String {
        switch product.id {
        case TearoffProduct.proMonthly: "Billed monthly"
        case TearoffProduct.proYearly: "Billed yearly — best value"
        case TearoffProduct.proLifetime: "One-time — yours forever, Family Sharing"
        default: product.description
        }
    }

    private var restoreAndTerms: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") { Task { await store.restore() } }
                .font(.footnote)
                .disabled(store.isWorking)
            Text("Free forever: manual receipts, expiry alerts, and your full vault. Pro sells time saved, never access to your own records.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

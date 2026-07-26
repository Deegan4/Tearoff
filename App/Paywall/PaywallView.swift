import SwiftUI
import StoreKit
import VaultCore

/// Tearoff Pro paywall. Insurance-shaped framing (spec §7): the pitch is
/// computed from the user's own vault — the dollars they have on the line
/// right now.
///
/// Scanning copy is deliberately unconditional. It previously branched on
/// Apple Intelligence availability and told A16-and-earlier devices that
/// "this device can't run on-device extraction" — which was false: the scan
/// path is Vision OCR plus the pure-Swift ReceiptParser and runs everywhere.
/// The branch sold those users short on a capability they already had.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: StoreManager

    /// Total value of purchases still inside an open return window, in cents.
    /// Drives the headline; zero falls back to generic copy.
    private let valueInWindowCents: Int

    init(store: StoreManager, valueInWindowCents: Int) {
        self.store = store
        self.valueInWindowCents = valueInWindowCents
    }

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
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 3.5)))
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
            benefit(0, "camera.viewfinder", "Camera receipt scanning",
                    "Snap the slip; Tearoff reads the merchant, date, total, and return terms straight off it.")
            benefit(1, "shield.lefthalf.filled", "Warranty tracking", "Track manufacturer warranty deadlines alongside returns.")
            benefit(2, "widget.small", "Widgets", "Upcoming deadlines on your Home Screen — with snooze and mark-returned built in.")
            benefit(3, "location", "Proximity reminders", "A nudge when you're back near a store with an open return window.")
            benefit(4, "arrow.up.forward.app", "Direct return links", "One tap straight to a retailer's returns page, not a search.")
            benefit(5, "square.and.arrow.up", "Export", "Your vault as a CSV, or a yearly PDF report of spend and deadlines.")
        }
    }

    private func benefit(_ index: Int, _ icon: String, _ title: String, _ subtitle: String) -> some View {
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
        .staggeredAppear(index)
    }

    @ViewBuilder
    private var products: some View {
        // Products load asynchronously, so this swap is on the path of every
        // paywall open — an un-animated cut here is the most-seen jank in the
        // app. Fade always; only lift under normal motion settings.
        Group {
            if store.displayProducts.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical)
                    .transition(.opacity)
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
                        .buttonStyle(.pressableCard)
                        .disabled(store.isWorking)
                    }
                }
                .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(y: 10)))
                // A purchase in flight is otherwise invisible: `isWorking` only
                // disabled the buttons, with no signal that a tap registered.
                .overlay {
                    if store.isWorking {
                        ProgressView()
                            .controlSize(.large)
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .transition(.opacity)
                            .accessibilityLabel("Completing purchase")
                    }
                }
                .animation(Motion.snappy, value: store.isWorking)
            }
        }
        .animation(Motion.premium, value: store.displayProducts.isEmpty)
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
            // Guideline 3.1.2(a): the subscription purchase screen itself must
            // link to both documents, not just the app's Settings/metadata.
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://deegan4.github.io/Tearoff/privacy.html")!)
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.caption)
            Text("Free forever: manual receipts, expiry alerts, and your full vault. Pro sells time saved, never access to your own records.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

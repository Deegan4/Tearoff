import Foundation
import Observation
import StoreKit
import VaultCore

/// StoreKit 2 entitlement state. Loads the three Pro products, tracks the
/// user's currently-active entitlements, and exposes the resolved tier. The
/// "which transactions still count" decision is StoreKit's
/// (`Transaction.currentEntitlements`); mapping the resulting identifiers to a
/// tier is VaultCore's pure `Entitlement`, so this class is a thin,
/// side-effecting shell around tested logic.
@MainActor
@Observable
final class StoreManager {
    /// Outcome of the last `loadProducts()`. The paywall must be able to tell
    /// "still loading" from "the store gave us nothing" — collapsing both into
    /// an empty array left the sheet spinning forever with no way back.
    enum ProductLoadState: Equatable {
        case loading
        case loaded
        /// The request succeeded but returned no products. Usually means the
        /// products are not yet approved/available in App Store Connect, or
        /// aren't offered in this storefront.
        case unavailable
        /// The request itself failed — offline, or StoreKit error.
        case failed
    }

    private(set) var loadState: ProductLoadState = .loading
    private(set) var products: [Product] = []
    private(set) var activeProductIDs: Set<String> = []
    /// Set while a purchase or restore is in flight, to disable the paywall CTAs.
    private(set) var isWorking = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    var tier: ProTier { Entitlement.tier(activeProductIDs: activeProductIDs) }

    var isPro: Bool {
        // The environment check is deliberately *here* as well as on the UI:
        // an App Store build must never honour this flag, even if the stored
        // value carried over from a TestFlight install on the same device.
        if BuildEnvironment.allowsDeveloperTools && debugProUnlock { return true }
        return tier.isPro
    }

    /// Dev unlock for Pro features. Debug builds have no purchasable products
    /// (the StoreKit config only loads under an Xcode run) and TestFlight
    /// testers can't buy until the products are approved, so without this Pro
    /// is unreachable in both. Toggle it in Settings → Developer.
    ///
    /// Defaults **on** in Debug for convenience, but **off** in TestFlight so
    /// it never silently masks a real sandbox purchase during testing.
    var debugProUnlock: Bool = {
        if let stored = UserDefaults.standard.object(forKey: "tearoff.debugProUnlock") as? Bool {
            return stored
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }() {
        didSet { UserDefaults.standard.set(debugProUnlock, forKey: "tearoff.debugProUnlock") }
    }

    /// Products sorted for display: monthly, yearly, then lifetime.
    var displayProducts: [Product] {
        let order = [TearoffProduct.proMonthly, TearoffProduct.proYearly, TearoffProduct.proLifetime]
        return products.sorted {
            (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
        }
    }

    init() {
        // Listen for transactions that arrive outside a direct purchase call
        // (renewals, restores from another device, Ask-to-Buy approvals).
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if (try? update.payloadValue) != nil {
                    await self.refreshEntitlements()
                }
            }
        }
    }

    deinit { updates?.cancel() }

    func loadProducts() async {
        loadState = .loading
        do {
            products = try await Product.products(for: TearoffProduct.proGranting)
            loadState = products.isEmpty ? .unavailable : .loaded
        } catch {
            products = []
            loadState = .failed
        }
        await refreshEntitlements()
    }

    /// Recompute active entitlements from StoreKit's verified current set.
    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement else { continue }
            if transaction.revocationDate == nil { owned.insert(transaction.productID) }
        }
        activeProductIDs = owned
    }

    /// Purchase a product. Returns true on a verified, completed purchase.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                guard case let .verified(transaction) = verification else { return false }
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// Restore purchases (App Store sync), then recompute entitlements.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}

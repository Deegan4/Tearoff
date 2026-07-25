import Foundation
import VaultCore

/// Bridges persistence records to VaultCore resolution. Held as a single
/// shared instance so the bundled tables are parsed once, not per row.
@MainActor
final class ResolverStore {
    static let shared = ResolverStore()

    let policy: PolicyResolver
    let warranty: WarrantyResolver

    private init() {
        let table = (try? PolicyTable.bundled()) ?? PolicyTable(rules: [])
        self.policy = PolicyResolver(table: table)
        self.warranty = (try? WarrantyResolver.bundled()) ?? WarrantyResolver(defaults: [:])
    }

    func returnWindow(for purchase: StoredPurchase) -> WindowResolution? {
        policy.resolve(
            merchant: purchase.merchant,
            category: purchase.category,
            purchaseDate: purchase.purchaseDate,
            printedWindowDays: purchase.printedWindowDays,
            userWindowDays: purchase.userWindowDays
        )
    }

    func warrantyWindow(for purchase: StoredPurchase) -> WindowResolution? {
        warranty.resolve(
            category: purchase.category,
            purchaseDate: purchase.purchaseDate,
            printedMonths: purchase.printedWarrantyMonths,
            userMonths: purchase.userWarrantyMonths
        )
    }

    /// Vault-wide insights (totals, open-return value, active warranties) for a
    /// set of stored purchases, resolved through the bundled tables. The single
    /// place that maps persistence records into VaultCore's pure `InsightsInput`,
    /// so views never re-implement it.
    func insights(for purchases: [StoredPurchase], now: Date = Date()) -> InsightsSummary {
        let inputs = purchases.map { p in
            InsightsInput(
                category: p.category.displayName,
                totalCents: p.totalCents.raw,
                isActive: !p.status.isResolved,
                returnDeadline: returnWindow(for: p)?.deadline,
                warrantyDeadline: warrantyWindow(for: p)?.deadline)
        }
        return VaultInsights.summary(inputs, now: now)
    }
}

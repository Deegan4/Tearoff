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

    /// Where the vault sits on the (purely cosmetic) rank ladder.
    ///
    /// `scansConfirmed` comes from the accuracy ledger rather than the vault
    /// because it is a lifetime running count — a scanned receipt that was
    /// later deleted still happened. Purchases and returns are read from the
    /// current vault, so callers that must not demote should feed the result
    /// through a high-water mark (see `SettingsView.bestXP`).
    func rankProgress(for purchases: [StoredPurchase], scansConfirmed: Int) -> RankProgress {
        RankLadder.progress(
            purchasesTracked: purchases.count,
            scansConfirmed: scansConfirmed,
            returnsCompleted: purchases.count { $0.status == .returned || $0.status == .refunded }
        )
    }
}

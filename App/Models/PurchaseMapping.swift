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
}

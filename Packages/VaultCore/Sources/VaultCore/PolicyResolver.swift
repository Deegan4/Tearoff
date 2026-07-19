import Foundation

/// Resolves a return deadline through a strict authority ladder.
///
/// The model is never consulted for policy duration — that is world
/// knowledge, which the on-device model is not built for and will
/// confabulate. Duration comes from the receipt, the curated table, or the
/// user, and from nowhere else.
public struct PolicyResolver: Sendable {
    private let table: PolicyTable

    public init(table: PolicyTable) {
        self.table = table
    }

    public func resolve(
        merchant: String,
        category: PurchaseCategory,
        purchaseDate: Date,
        printedWindowDays: Int?,
        userWindowDays: Int?
    ) -> WindowResolution? {
        // Consumables never carry a countdown, regardless of merchant policy.
        guard category.isReturnable else { return nil }

        if let days = userWindowDays, days > 0 {
            return WindowResolution(purchaseDate: purchaseDate, days: days, provenance: .user)
        }

        if let days = printedWindowDays, days > 0 {
            return WindowResolution(purchaseDate: purchaseDate, days: days, provenance: .printed)
        }

        let key = PolicyTable.normalize(merchant)
        if let rule = table.rule(merchantKey: key, category: category, on: purchaseDate) {
            return WindowResolution(purchaseDate: purchaseDate, days: rule.windowDays, provenance: .table)
        }

        return nil
    }
}

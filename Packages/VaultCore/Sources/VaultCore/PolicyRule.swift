import Foundation

/// One retailer return-policy rule, valid from `effectiveDate` onward.
///
/// Rules are append-only. To record a policy change, add a new rule with a
/// later `effectiveDate`; never edit an existing one. Purchases resolve
/// against the rule that was in force on their purchase date.
public struct PolicyRule: Hashable, Codable, Sendable {
    public let merchantKey: String
    /// `nil` means the rule applies to every category at this merchant.
    public let category: PurchaseCategory?
    public let windowDays: Int
    public let effectiveDate: Date

    public init(merchantKey: String, category: PurchaseCategory?, windowDays: Int, effectiveDate: Date) {
        self.merchantKey = merchantKey
        self.category = category
        self.windowDays = windowDays
        self.effectiveDate = effectiveDate
    }
}

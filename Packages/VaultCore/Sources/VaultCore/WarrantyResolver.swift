import Foundation

/// Resolves a warranty expiry date.
///
/// Return windows come from the merchant; warranty terms come from the
/// manufacturer. The merchant-keyed policy table therefore cannot answer
/// this, so the ladder is: user override, printed term, conservative
/// category default (labelled an estimate), or nothing.
public struct WarrantyResolver: Sendable {
    private let defaults: [PurchaseCategory: Int]  // months

    public init(defaults: [PurchaseCategory: Int]) {
        self.defaults = defaults
    }

    public func resolve(
        category: PurchaseCategory,
        purchaseDate: Date,
        printedMonths: Int?,
        userMonths: Int?
    ) -> WindowResolution? {
        guard category.isReturnable else { return nil }

        let calendar = Calendar.utcGregorian

        func resolution(months: Int, provenance: Provenance) -> WindowResolution? {
            guard months > 0,
                  let deadline = calendar.date(byAdding: .month, value: months, to: purchaseDate)
            else { return nil }
            let days = calendar.dateComponents([.day], from: purchaseDate, to: deadline).day ?? 0
            return WindowResolution(purchaseDate: purchaseDate, days: days, provenance: provenance)
        }

        if let months = userMonths { return resolution(months: months, provenance: .user) }
        if let months = printedMonths { return resolution(months: months, provenance: .printed) }
        if let months = defaults[category] { return resolution(months: months, provenance: .categoryDefault) }

        return nil
    }

    public static func bundled() throws -> WarrantyResolver {
        guard let url = Bundle.module.url(forResource: "warranty-defaults", withExtension: "json") else {
            throw PolicyTableError.resourceMissing
        }
        let raw = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
        var defaults: [PurchaseCategory: Int] = [:]
        for (key, months) in raw {
            if let category = PurchaseCategory(rawValue: key) { defaults[category] = months }
        }
        return WarrantyResolver(defaults: defaults)
    }
}

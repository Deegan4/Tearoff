import Foundation

public struct PolicyTable: Sendable {
    private let rules: [PolicyRule]

    public init(rules: [PolicyRule]) {
        self.rules = rules
    }

    public var merchantCount: Int {
        Set(rules.map(\.merchantKey)).count
    }

    /// Collapses receipt spelling variance to a stable key. Receipts print
    /// "BEST BUY #1234", "Best Buy", and "BESTBUY.COM" for the same retailer.
    public static func normalize(_ merchant: String) -> String {
        merchant
            .lowercased()
            .replacingOccurrences(of: ".com", with: "")
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// The rule in force at `date`, preferring a category-specific rule over
    /// a general one when both are in force.
    public func rule(merchantKey: String, category: PurchaseCategory, on date: Date) -> PolicyRule? {
        let inForce = rules.filter {
            $0.merchantKey == merchantKey
                && $0.effectiveDate <= date
                && ($0.category == nil || $0.category == category)
        }

        return inForce.max { lhs, rhs in
            if lhs.effectiveDate != rhs.effectiveDate {
                return lhs.effectiveDate < rhs.effectiveDate
            }
            // Same effective date: category-specific outranks general.
            return (lhs.category == nil) && (rhs.category != nil)
        }
    }

    public static func bundled() throws -> PolicyTable {
        guard let url = Bundle.module.url(forResource: "return-policies", withExtension: "json") else {
            throw PolicyTableError.resourceMissing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules = try decoder.decode([PolicyRule].self, from: Data(contentsOf: url))
        return PolicyTable(rules: rules)
    }
}

public enum PolicyTableError: Error {
    case resourceMissing
}
